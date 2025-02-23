// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("CoreTokenModule", (m) => {
  const _admin = m.getParameter(
    "_admin",
    "0x..."
  );
  const _coreTreasury = m.getParameter(
    "_coreTreasury",
    "0x..."
  );

  const coreToken = m.contract("CoreToken", [_admin, _coreTreasury]);

  return { coreToken };
});
