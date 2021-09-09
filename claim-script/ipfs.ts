import axios from 'axios';

export default class IpfsService {
  gateway: string;

  constructor() {
    this.gateway = 'https://ipfs.infura.io:5001/api/v0/cat';
  }

  async get<T>(hash: string): Promise<T> {
    const { data } = await axios.get(`${this.gateway}/${hash}`);
    return data;
  }
}

export const ipfsService = new IpfsService();
