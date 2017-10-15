const promisify = (fn) =>
  new Promise((resolve, reject) =>
    fn((err, res) => {
      if (err) { reject(err); }
      resolve(res);
    })
  );

const getBalance = (account, at) =>
  promisify(cb => web3.eth.getBalance(account, at, cb));

const getEvents = (watcher) => promisify(cb => watcher.get(cb));

const getBlock = (blockNumber) =>
  promisify(cb =>web3.eth.getBlock(blockNumber, cb));

const assertThrow = async (fn, ...args) => {
  try {
    await fn.apply(this, args)
  } catch (err) {
    return;
  }

  throw new Error('should throw an error');
}

const timeJump = (seconds) =>
  promisify(cb => web3.currentProvider.sendAsync({
    jsonrpc: "2.0",
    method: "evm_increaseTime",
    params: [seconds],
    id: new Date().getTime()
  }, cb));

module.exports = {
  promisify,
  getBalance,
  getEvents,
  getBlock,
  assertThrow,
  timeJump,
};
