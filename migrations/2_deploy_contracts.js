const ANTToken = artifacts.require('ANTToken');
const USDToken = artifacts.require('USDToken');
const oraclizeLib = artifacts.require('oraclizeLib');
const Payroll = artifacts.require('Payroll');
const PayrollDB = artifacts.require('PayrollDB');

async function deploy(deployer) {
  let db;

  await deployer.deploy([
    ANTToken,
    USDToken,
    oraclizeLib,
    PayrollDB,
  ]);

  deployer.link(oraclizeLib, Payroll);
  await deployer.deploy(Payroll,PayrollDB.address, ANTToken.address,
    USDToken.address);

  db = await PayrollDB.deployed();
  await db.setAllowedContract([Payroll.address]);
}

module.exports = function(deployer) {
  deployer.then(() => deploy(deployer));
};
