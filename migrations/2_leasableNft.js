const leasableNftCont = artifacts.require("LeasableNft");

const { setEnvValue } = require("../utils/env-man");

const conf = require("../migration-parameters");

const setLeasableNft = (n, v) => {
  setEnvValue("../", `LeasableNft_ADDRESS${n.toUpperCase()}`, v);
};

module.exports = async (deployer, network, accounts) => {
  switch (network) {
    case "rinkeby":
      c = { ...conf.rinkeby };
      break;
    case "mainnet":
      c = { ...conf.mainnet };
      break;
    case "development":
    default:
      c = { ...conf.devnet };
  }

  // deploy LeasableNft
  await deployer.deploy(
    leasableNftCont,
    c.name,
    c.symbol,
    c.baseTokenURI,
    c.notRevealedURI,
    c.mintPrice,
    c.mintingLimit,
    c.maxTokenId
  );

  const leasableNft = await leasableNftCont.deployed();

  if (leasableNft) {
    console.log(
      `Deployed: LeasableNft
       network: ${network}
       address: ${leasableNft.address}
       creator: ${accounts[0]}
    `
    );
    setLeasableNft(network, leasableNft.address);
  } else {
    console.log("LeasableNft Deployment UNSUCCESSFUL");
  }
};
