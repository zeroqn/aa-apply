const ANTToken = artifacts.require('ANTToken');
const USDToken = artifacts.require('USDToken');
const oraclizeLib = artifacts.require('oraclizeLib');
const Payroll = artifacts.require('Payroll');
const PayrollDB = artifacts.require('PayrollDB');
const EscapeHatch = artifacts.require('EscapeHatch');
const EmployeeServ = artifacts.require('EmployeeServ');
const PaymentServ = artifacts.require('PaymentServ');

async function deploy(deployer) {
  let db;
  let serv;
  let hatch;

  await deployer.deploy([
    ANTToken,
    USDToken,
    oraclizeLib,
    PayrollDB,
    EscapeHatch,
  ]);

  await deployer.deploy(EmployeeServ, PayrollDB.address);
  deployer.link(oraclizeLib, PaymentServ);
  await deployer.deploy(PaymentServ, PayrollDB.address, ANTToken.address,
    USDToken.address, EscapeHatch.address);

  await deployer.deploy(Payroll, EmployeeServ.address, PaymentServ.address);

  serv = await EmployeeServ.deployed();
  await serv.setPayrollAddress(Payroll.address);
  serv = await PaymentServ.deployed();
  await serv.setPayrollAddress(Payroll.address);

  db = await PayrollDB.deployed();
  await db.setAllowedContract([EmployeeServ.address, PaymentServ.address]);

  hatch = await EscapeHatch.deployed();
  await hatch.setPayment(PaymentServ.address);
}

module.exports = function(deployer) {
  deployer.then(() => deploy(deployer));
};
