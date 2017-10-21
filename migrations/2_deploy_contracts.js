const ANTToken = artifacts.require('ANTToken');
const USDToken = artifacts.require('USDToken');
const oraclizeLib = artifacts.require('oraclizeLib');
const Payroll = artifacts.require('Payroll');
const PayrollDB = artifacts.require('PayrollDB');
const EscapeHatch = artifacts.require('EscapeHatch');

async function deploy(deployer) {
  let db;
  let hatch;

  await deployer.deploy([
    ANTToken,
    USDToken,
    oraclizeLib,
    PayrollDB,
    EscapeHatch,
  ]);

  deployer.link(oraclizeLib, Payroll);
  await deployer.deploy(Payroll, PayrollDB.address, ANTToken.address,
    USDToken.address, EscapeHatch.address);

  db = await PayrollDB.deployed();
  await db.setAllowedContract([Payroll.address]);

  hatch = await EscapeHatch.deployed();
  await hatch.setPayroll(Payroll.address);
}

module.exports = function(deployer) {
  deployer.then(() => deploy(deployer));
};
