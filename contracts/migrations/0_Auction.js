const { MichelsonMap } = require('@taquito/taquito')
const { Buffer } = require('buffer')
const { buf2hex } = require('@taquito/utils')
const fa2 = artifacts.require("Auction");

module.exports = async(deployer, _network, accounts)  => {
    Tezos.contract
    .at('KT1WQgF1AfWkTUebpCERG3jiUtUzAanJp4xJ')
    .then((c) => {
      let methods = c.parameterSchema.ExtractSignatures();
      println(JSON.stringify(methods, null, 2));
    })
    .catch((error) => console.log(`Error: ${error}`));
};
