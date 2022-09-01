const Marketplace = artifacts.require("Marketplace");
const NFTFactory = artifacts.require("NFTFactory");

module.exports = async function (deployer) {
  await deployer.deploy(Marketplace,86400*5,86400,86400*10);
  await deployer.deploy(NFTFactory,"0x0000000000000000000000000000000000000000");
};
