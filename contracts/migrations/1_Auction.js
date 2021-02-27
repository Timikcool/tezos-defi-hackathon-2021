const { MichelsonMap } = require('@taquito/taquito')
const { Buffer } = require('buffer')
const { buf2hex } = require('@taquito/utils')
const fa2 = artifacts.require("Auction");

module.exports = async(deployer, _network, accounts)  => {
    const meta = { 
        "name": "NFT Button Auction", 
        "description": "Simple NFT auction",
    }

    const houseOwner = accounts[0]
    const bidders = new MichelsonMap();
    const metadata = new MichelsonMap();
    const auctions = new MichelsonMap();

    metadata.set("", buf2hex("tezos-storage:data"))
    metadata.set("data", buf2hex(Buffer.from(JSON.stringify(meta))))

    deployer.deploy(fa2, { metadata, bidders, auctions, houseOwner, nextId: 1, houseBank: 0 });
};
