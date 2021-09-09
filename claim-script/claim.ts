import { Contract } from '@ethersproject/contracts';
import { parseUnits } from '@ethersproject/units';
import { TransactionResponse, JsonRpcProvider } from '@ethersproject/providers';
import { BigNumberish } from '@ethersproject/bignumber';
import { toWei, soliditySha3 } from 'web3-utils';
import axios from 'axios';

import { ipfsService } from './ipfs';
import { loadTree } from './merkle';

import merkleRedeemAbi from './abi/MerkleRedeem.json';

type NetworkId = 1 | 3 | 4 | 5 | 42 | 137 | 42161;

interface Claim {
  id: string;
  amount: string;
  amountDenorm: BigNumberish;
}

type Snapshot = Record<number, string>;

async function call(
  provider: JsonRpcProvider,
  abi: any[],
  call: any[],
  options?: any
) {
  const contract = new Contract(call[0], abi, provider);
  try {
    const params = call[2] || [];
    return await contract[call[1]](...params, options || {});
  } catch (e) {
    return Promise.reject(e);
  }
}

// @ts-ignore
export const constants: Record<NetworkId, Record<string, string>> = {
  1: {
    merkleRedeem: '0x6d19b2bF3A36A61530909Ae65445a906D98A2Fa8',
    snapshot:
      'https://raw.githubusercontent.com/balancer-labs/bal-mining-scripts/master/reports/_current.json',
  },
  42: {
    merkleRedeem: '0x3bc73D276EEE8cA9424Ecb922375A0357c1833B3',
    snapshot:
      'https://raw.githubusercontent.com/balancer-labs/bal-mining-scripts/master/reports-kovan/_current.json',
  },
};

export async function getSnapshot(network: NetworkId) {
  if (constants[network]?.snapshot) {
    const response = await axios.get<Snapshot>(constants[network].snapshot);
    return response.data || {};
  }
  return {};
}

type ClaimStatus = boolean;

export async function getClaimStatus(
  network: NetworkId,
  provider: JsonRpcProvider,
  ids: number,
  account: string
): Promise<ClaimStatus[]> {
  return await call(provider, merkleRedeemAbi, [
    constants[network].merkleRedeem,
    'claimStatus',
    [account, 1, ids],
  ]);
}

export type Report = Record<string, any>;

export async function getReports(snapshot: Snapshot, weeks: number[]) {
  const reports = await Promise.all<Report>(
    weeks.map((week) => ipfsService.get(snapshot[week]))
  );
  return Object.fromEntries(reports.map((report, i) => [weeks[i], report]));
}

export async function getPendingClaims(
  network: NetworkId,
  provider: JsonRpcProvider,
  account: string
): Promise<{ claims: Claim[]; reports: Report }> {
  if (!constants[network]) {
    return {
      claims: [],
      reports: {},
    };
  }
  const snapshot = await getSnapshot(network);

  const claimStatus = await getClaimStatus(
    network,
    provider,
    Object.keys(snapshot).length,
    account
  );

  const pendingWeeks = claimStatus
    .map((status, i) => [i + 1, status])
    // .filter(([, status]) => !status)
    .map(([i]) => i) as number[];

  const pendingWeeksReports = await getReports(snapshot, pendingWeeks);
  return {
    claims: Object.entries(pendingWeeksReports)
      .filter((report: Report) => report[1][account])
      .map((report: Report) => {
        return {
          id: report[0],
          amount: report[1][account],
          amountDenorm: parseUnits(report[1][account], 18),
        };
      }),
    reports: pendingWeeksReports,
  };
}

export async function claimRewards(
  account: string,
  pendingClaims: Claim[],
  reports: Report
) {
  try {
    const claims = pendingClaims.map((week) => {
      const claimBalance = week.amount;
      const merkleTree = loadTree(reports[week.id]);

      const proof = merkleTree.getHexProof(
        soliditySha3(account, toWei(claimBalance))
      );
      return [parseInt(week.id), toWei(claimBalance), proof];
    });

    console.log('Claims', claims);
  } catch (e) {
    console.log('[Claim] Claim Rewards Error:', e);
    return Promise.reject(e);
  }
}
