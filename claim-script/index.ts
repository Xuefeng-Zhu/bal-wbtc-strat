import { JsonRpcProvider } from '@ethersproject/providers';
import { getPendingClaims, claimRewards } from './claim';

const provider = new JsonRpcProvider('https://api.mycryptoapi.com/eth');
const account = '0x3F86c3A4D4857a6F92999f214e2eD3aE7BB852C1';

async function main() {
  try {
    const { claims, reports } = await getPendingClaims(1, provider, account);

    claimRewards(account, claims, reports);
  } catch (e) {
    console.log(e);
  }
}

main();
