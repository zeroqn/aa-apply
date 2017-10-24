const ANTToken = artifacts.require('ANTToken');
const USDToken = artifacts.require('USDToken');
const Payroll = artifacts.require('Payroll');
const PayrollDB = artifacts.require('PayrollDB');
const EscapeHatch = artifacts.require('EscapeHatch');
const EmployeeServ = artifacts.require('EmployeeServ');
const PaymentServ = artifacts.require('PaymentServ');

const helper = require('./helper');

contract('Payroll', (accounts) => {
  const owner = accounts[0];
  const testEmployee = accounts[2];
  const testYearlyUSDSalary = 1200;
  const exchangeRate = 2;
  const tokenAmount = 200;
  let antToken;
  let usdToken;
  let allowedTokens;
  let payroll;
  let testEmployeeId;
  let hatch;
  let employeeServ;
  let paymentServ;

  before(async () => {
    antToken = await ANTToken.deployed();
    usdToken = await USDToken.deployed();
    allowedTokens = [antToken.address, usdToken.address];
  });

  beforeEach(async () => {
    let db = await PayrollDB.new();
    hatch = await EscapeHatch.new();
    employeeServ = await EmployeeServ.new(db.address);
    paymentServ = await PaymentServ.new(db.address, antToken.address,
      usdToken.address, hatch.address);
    payroll = await Payroll.new(employeeServ.address, paymentServ.address);

    await employeeServ.setPayrollAddress(payroll.address);
    await paymentServ.setPayrollAddress(payroll.address);
    await hatch.setPayment(paymentServ.address);
    await db.setAllowedContract([employeeServ.address, paymentServ.address]);

    const ETH_SYM_ADDR = await paymentServ.ETH_SYM_ADDR.call();

    // 200 ETH + 200 USD + 200 ANT
    await antToken.mint(paymentServ.address, tokenAmount);
    await usdToken.mint(paymentServ.address, tokenAmount);
    await payroll.addFunds({from: testEmployee, value: tokenAmount});
    await payroll.setExchangeRate(antToken.address, exchangeRate);
    await payroll.setExchangeRate(ETH_SYM_ADDR, exchangeRate);

    await payroll.addEmployee(testEmployee, allowedTokens,
      testYearlyUSDSalary, {from: owner});
    testEmployeeId = (await payroll.getEmployeeId.call(testEmployee))
      .toNumber();
  });

  it('should add new employee', async () => {
    let events;

    await payroll.addEmployee(accounts[1], allowedTokens, 2400, {from: owner});
    events = await helper.getEvents(payroll.OnEmployeeAdded());
    assert.equal(events.length, 1);
    assert.equal(events[0].args.account, accounts[1]);
    assert.equal(events[0].args.yearlyUSDSalary.toNumber(), 2400);
  });

  it('should not add new employee from sender other than owner', async () => {
    await helper.assertThrow(payroll.addEmployee, accounts[1], allowedTokens,
      2400, {from: testEmployee});
  });

  it('should not add new employee if account address is 0x0', async () => {
    await helper.assertThrow(payroll.addEmployee, 0x0, allowedTokens, 2400,
      {from: owner});
  });

  it('should not add new employee if one of token address is 0x0', async () => {
    await helper.assertThrow(payroll.addEmployee, accounts[1], [0x0], 2400,
      {from: owner});
  });

  it('should not add new employee if yearlyUSDSalary mod 12 isnt 0',
    async () => {
      await helper.assertThrow(payroll.addEmployee, accounts[1], allowedTokens,
        2000, {from: owner});
    });

  it('should set employee yearly usd salary', async () => {
    const newYearlyUSDSalary = testYearlyUSDSalary + 12 * 3 * 1000;
    let events;

    await payroll.setEmployeeSalary(testEmployeeId, newYearlyUSDSalary,
      {from: owner});
    events = await helper.getEvents(payroll.OnEmployeeSalaryUpdated());

    assert.equal(events.length, 1);
    assert.equal(events[0].args.employeeId.toNumber(), testEmployeeId);
    assert.equal(events[0].args.yearlyUSDSalary.toNumber(), newYearlyUSDSalary);
  });

  it('should not set employee yearly usd salary from sender other than owner',
    async () => {
      await helper.assertThrow(payroll.setEmployeeSalary, testEmployeeId,
        testYearlyUSDSalary, {from: testEmployee});
    });

  it('should not set employee yearly usd salary to 0', async () => {
    await helper.assertThrow(payroll.setEmployeeSalary, testEmployeeId,
      0, {from: owner});
  });

  it('should not set employee yearly usd salary if it mod 12 isnt 0',
    async () => {
      await helper.assertThrow(payroll.setEmployeeSalary, testEmployeeId,
        2000, {from: owner});
    });

  it('should remove the employee using employeeId', async () => {
    let events;

    await payroll.removeEmployee(testEmployeeId, {from: owner});
    events = await helper.getEvents(payroll.OnEmployeeRemoved());
    let [active, ...rest] = await payroll.getEmployee.call(testEmployeeId);

    assert.equal(events.length, 1);
    assert.equal(events[0].args.employeeId.toNumber(), testEmployeeId);
    assert.isFalse(active);
  });

  it('should not remove the employee from sender other than owner',
    async () => {
      await helper.assertThrow(payroll.removeEmployee, testEmployeeId,
        {from: testEmployeeId});
    });

  it('should return employee count', async () => {
    let count;

    count = await payroll.getEmployeeCount.call();
    assert.equal(count.toNumber(), 1);

    await payroll.addEmployee(accounts[1], allowedTokens,
      testYearlyUSDSalary, {from: owner});
    count = await payroll.getEmployeeCount.call();
    assert.equal(count.toNumber(), 2);

    await payroll.removeEmployee(testEmployeeId, {from: owner});
    count = await payroll.getEmployeeCount.call();
    assert.equal(count.toNumber(), 1);
  });

  it('should return employee info', async () => {
    let [active, account, yearlyUSDSalary] = await payroll.getEmployee.call(
      testEmployeeId);

    assert.isTrue(active);
    assert.equal(account, testEmployee);
    assert.equal(yearlyUSDSalary.toNumber(), testYearlyUSDSalary);
  });

  it('should add eth funds', async () => {
    let events;
    let amount;

    await payroll.addFunds({from: testEmployee, value: 10000});
    events = await helper.getEvents(payroll.OnEthFundsAdded());
    amount = await helper.getBalance(paymentServ.address);

    assert.equal(events.length, 1);
    assert.equal(events[0].args.from, testEmployee);
    assert.equal(events[0].args.amount.toNumber(), 10000);
    assert.equal(amount.toNumber(), 10000 + tokenAmount);
  });

  it('should pause contract after call pause', async () => {
    let events;
    await payroll.pause({from: owner});
    events = await helper.getEvents(payroll.Pause());

    assert.equal(events.length, 1);
    assert.equal(events[0].event, 'Pause');
  });

  it('should not pause contract from sender other than owner', async () => {
    await helper.assertThrow(payroll.pause, {from: testEmployee});
  });

  it('should return monthly salaries burnrate', async () => {
    let burnrate = await payroll.calculatePayrollBurnrate.call();

    assert.equal(burnrate.toNumber(), testYearlyUSDSalary / 12);
  });

  it('should allow emergency withdraw after pause', async () => {
    let amount;
    let prevANTAmount;
    let prevUSDAmount;

    await payroll.addFunds({from: testEmployee, value: 10000});

    amount = await helper.getBalance(paymentServ.address);
    assert.equal(amount.toNumber(), 10000 + tokenAmount);
    amount = await antToken.balanceOf(paymentServ.address);
    assert.equal(amount.toNumber(), tokenAmount);
    amount = await usdToken.balanceOf(paymentServ.address);
    assert.equal(amount.toNumber(), tokenAmount);
    prevANTAmount = await antToken.balanceOf(owner);
    prevUSDAmount = await usdToken.balanceOf(owner);

    await payroll.pause({from: owner});
    await payroll.emergencyWithdraw({from: owner})

    amount = await helper.getBalance(paymentServ.address);
    assert.equal(amount.toNumber(), 0);
    amount = await antToken.balanceOf(paymentServ.address);
    assert.equal(amount.toNumber(), 0);
    amount = await usdToken.balanceOf(paymentServ.address);
    assert.equal(amount.toNumber(), 0);

    amount = await antToken.balanceOf(owner);
    assert.equal(amount.toNumber(), prevANTAmount + tokenAmount);
    amount = await usdToken.balanceOf(owner);
    assert.equal(amount.toNumber(), prevUSDAmount + tokenAmount);
  });

  it('should not allow emergencyWithdraw from sender other than owner',
    async () => {
      await payroll.pause({from: owner});
      await helper.assertThrow(payroll.emergencyWithdraw, {from: testEmployee});
    });

  it('should now allow emergencyWithdraw if payroll isnt paused',
    async () => {
      await helper.assertThrow(payroll.emergencyWithdraw, {from: owner});
    });

  it('should return runway', async () => {
    await payroll.addFunds({from: testEmployee, value: tokenAmount});
    await payroll.calculatePayrollRunway();
  });

  it('should return runway in months', async () => {
    const monthlyUSDSalary = testYearlyUSDSalary / 12;
    // ant amount * exchange = usd amount
    // eth amount * exchange = usd amount
    const months = (tokenAmount + tokenAmount * exchangeRate * 2) /
      monthlyUSDSalary;
    let leftMonths;

    leftMonths = await payroll.calculatePayrollRunwayInMonths.call();
    assert.equal(leftMonths.toNumber(), months);
  });

  it('should allow employee to determine salary allocation', async () => {
    let events;

    await payroll.determineAllocation([antToken.address, usdToken.address],
      [20, 40], {from: testEmployee});
    events = await helper.getEvents(payroll.OnAllocationChanged());

    assert.equal(events.length, 2);
    assert.equal(events[0].args.employeeId.toNumber(), testEmployeeId);
    assert.equal(events[0].args.token, antToken.address);
    assert.equal(events[0].args.alloc.toNumber(), 20);
    assert.equal(events[1].args.employeeId.toNumber(), testEmployeeId);
    assert.equal(events[1].args.token, usdToken.address);
    assert.equal(events[1].args.alloc.toNumber(), 40);
  });

  it('should not allow employee to change salary allocation again in 6 months',
    async () => {
      const SIX_MONTHS = 60 * 60 * 24 * 31 * 6;
      let events;

      await payroll.determineAllocation([antToken.address, usdToken.address],
        [20, 40], {from: testEmployee});

      await helper.assertThrow(payroll.determineAllocation,
        [antToken.address, usdToken.address], [30, 50], {from: testEmployee});
      await helper.timeJump(SIX_MONTHS);
      await payroll.determineAllocation([antToken.address, usdToken.address],
        [30, 50], {from: testEmployee});
      events = await helper.getEvents(payroll.OnAllocationChanged());

      assert.equal(events.length, 2);
      assert.equal(events[0].args.employeeId.toNumber(), testEmployeeId);
      assert.equal(events[0].args.token, antToken.address);
      assert.equal(events[0].args.alloc.toNumber(), 30);
      assert.equal(events[1].args.employeeId.toNumber(), testEmployeeId);
      assert.equal(events[1].args.token, usdToken.address);
      assert.equal(events[1].args.alloc.toNumber(), 50);
    });

  it('should not allow employee change salary allocation if length isnt matched'
    , async () => {
      await helper.assertThrow(payroll.determineAllocation,
        [antToken.address, usdToken.address], [20], {from: testEmployee});
    });

  it('should not allow employee change salary alloc if token isnt allowed',
    async () => {
      await helper.assertThrow(payroll.determineAllocation,
        [testEmployee.address, usdToken.address], [20, 40],
        {from: testEmployee});
    });

  it('should not allow employee change salary alloc if one of dist exceed 100',
    async () => {
      await helper.assertThrow(payroll.determineAllocation,
        [antToken.address, usdToken.address], [20, 110], {from: testEmployee});
    });

  it('should not allow employee change salary alloc if sum of dist exceed 100',
    async () => {
      await helper.assertThrow(payroll.determineAllocation,
        [antToken.address, usdToken.address], [60, 50], {from: testEmployee});
    });

  it('should not change employee salary alloc from sender other than themself',
    async () => {
      await helper.assertThrow(payroll.determineAllocation,
        [antToken.address, usdToken.address], [20, 50], {from: owner});
    });

  it('should not change employee salary alloc after pause',
    async () => {
      await payroll.pause({from: owner});
      await helper.assertThrow(payroll.determineAllocation,
        [antToken.address, usdToken.address], [20, 50], {from: testEmployee});
    });

  it('should pay employee in payday', async () => {
    let events;
    let amount;

    // 1200 yearly salary / 12 => 100 monthly salary
    // 20% in USD  => 20 USD
    // 20% in ANT => 20 USD => 20 / 2 => 10 ANT
    // 60% in ETH => 60 USD => 60 / 2 => 30 ETH
    await payroll.determineAllocation([antToken.address, usdToken.address],
      [20, 20], {from: testEmployee});
    await payroll.payday({from: testEmployee});

    events = await helper.getEvents(payroll.OnPaid());
    assert.equal(events.length, 1);
    assert.equal(events[0].args.employeeId.toNumber(), testEmployeeId);
    assert.equal(events[0].args.monthlyUSDSalary.toNumber(),
      testYearlyUSDSalary / 12);

    events = await helper.getEvents(hatch.OnQuarantineToken());
    assert.equal(events.length, 2);
    assert.equal(events[0].args.employee, testEmployee);
    assert.equal(events[0].args.token, antToken.address);
    assert.equal(events[0].args.amount.toNumber(), 10);
    assert.equal(events[1].args.employee, testEmployee);
    assert.equal(events[1].args.token, usdToken.address);
    assert.equal(events[1].args.amount.toNumber(), 20);

    events = await helper.getEvents(hatch.OnQuarantineEth());
    assert.equal(events.length, 1);
    assert.equal(events[0].args.employee, testEmployee);
    assert.equal(events[0].args.amount.toNumber(), 30);

    amount = await helper.getBalance(hatch.address);
    assert.equal(amount.toNumber(), 30);
    amount = await antToken.balanceOf(hatch.address);
    assert.equal(amount.toNumber(), 10);
    amount = await usdToken.balanceOf(hatch.address);
    assert.equal(amount.toNumber(), 20);

    amount = await helper.getBalance(paymentServ.address);
    assert.equal(amount.toNumber(), tokenAmount - 30);
    amount = await antToken.balanceOf(paymentServ.address);
    assert.equal(amount.toNumber(), tokenAmount - 10);
    amount = await usdToken.balanceOf(paymentServ.address);
    assert.equal(amount.toNumber(), tokenAmount - 20);
  });

  it('should not pay employee again until one month later', async () => {
    const ONE_MONTH = 60 * 60 * 24 * 31;
    let events;

    await payroll.payday({from: testEmployee});
    await helper.assertThrow(payroll.payday, {from: testEmployee});
    await helper.timeJump(ONE_MONTH);
    await payroll.payday({from: testEmployee});
    events = await helper.getEvents(payroll.OnPaid());

    assert.equal(events.length, 1);
    assert.equal(events[0].args.employeeId.toNumber(), testEmployeeId);
    assert.equal(events[0].args.monthlyUSDSalary.toNumber(),
      testYearlyUSDSalary / 12);
  });

  it('should not pay from sender other than employee', async () => {
    await helper.assertThrow(payroll.payday, {from: owner});
  });

  it('should not pay employee after pause', async () => {
    await payroll.pause({from: owner});
    await helper.assertThrow(payroll.payday, {from: testEmployee});
  });

  it('should not pay employee after escapeHatch', async () => {
    await payroll.escapeHatch({from: owner});
    await helper.assertThrow(payroll.payday, {from: testEmployee});
  });

  it('should not able to call escape hatch from sender other than owner',
    async () => {
      await helper.assertThrow(payroll.escapeHatch, {from: testEmployee});
    });

  it('should not pay employee if hatch is paused', async () => {
    await hatch.pause({from: owner});
    await helper.assertThrow(payroll.payday, {from: testEmployee});
  });

  it('should allow employee withdraw salary from hatch after quarantine',
    async () => {
      let events;
      let amount;

      // 1200 yearly salary / 12 => 100 monthly salary
      // 20% in USD  => 20 USD
      // 20% in ANT => 20 USD => 20 / 2 => 10 ANT
      // 60% in ETH => 60 USD => 60 / 2 => 30 ETH
      await payroll.determineAllocation([antToken.address, usdToken.address],
        [20, 20], {from: testEmployee});
      await payroll.payday({from: testEmployee});

      await helper.assertThrow(hatch.withdraw, {from: testEmployee});
      await helper.timeJump(60 * 60 * 25);
      await hatch.withdraw({from: testEmployee});

      events = await helper.getEvents(hatch.OnWithdraw());
      assert.equal(events.length, 1);
      assert.equal(events[0].args.employee, testEmployee);

      amount = await antToken.balanceOf(testEmployee);
      assert.equal(amount.toNumber(), 10);
      amount = await usdToken.balanceOf(testEmployee);
      assert.equal(amount.toNumber(), 20);
    });

  it('should not allow withdraw if hatch is paused', async () => {
    await payroll.payday({from: testEmployee});
    await helper.timeJump(60 * 60 * 25);
    await hatch.pause({from: owner});
    await helper.assertThrow(hatch.withdraw, {from: testEmployee});
  });

  it('should allow emergency withdraw from hatch if paused', async () => {
    let events;
    let amount;
    let prevANTAmount;
    let prevUSDAmount;

    // 1200 yearly salary / 12 => 100 monthly salary
    // 20% in USD  => 20 USD
    // 20% in ANT => 20 USD => 20 / 2 => 10 ANT
    // 60% in ETH => 60 USD => 60 / 2 => 30 ETH
    await payroll.determineAllocation([antToken.address, usdToken.address],
      [20, 20], {from: testEmployee});
    await payroll.payday({from: testEmployee});
    await hatch.pause({from: owner});

    prevANTAmount = await antToken.balanceOf(owner);
    prevUSDAmount = await usdToken.balanceOf(owner);
    await hatch.emergencyWithdraw({from: owner});

    events = await helper.getEvents(hatch.OnEmergencyWithdraw());
    assert.equal(events.length, 1);
    assert.equal(events[0].event, 'OnEmergencyWithdraw');

    amount = await antToken.balanceOf(owner);
    assert.equal(amount.toNumber(), prevANTAmount.toNumber() + 10);
    amount = await usdToken.balanceOf(owner);
    assert.equal(amount.toNumber(), prevUSDAmount.toNumber() + 20);
  });

  it('should not allow emergency withdraw from hatch if its not paused',
    async () => {
      await payroll.payday({from: testEmployee});
      await helper.assertThrow(hatch.emergencyWithdraw, {from: owner});
    });

  it('should not allow emergency withdraw from hatch other than owner',
    async () => {
      await payroll.payday({from: testEmployee});
      await hatch.pause({from: owner});
      await helper.assertThrow(hatch.emergencyWithdraw, {from: testEmployee});
    });

});
