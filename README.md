# Logstash Blockchain Input Plugin

This Logstash input plugin queries your blockchain via the [RPC API](https://bitcoin.org/en/developer-reference#bitcoin-core-apis) and generates 
events for each block and/or transaction that it encounters. At the moment, both the [Bitcoin](https://bitcoin.org) and the 
[Ethereum](https://www.ethereum.org/) blockchains are supported and other ones may be added in the future.

## Prerequisite

### Ethereum blockchain

You need a fully synced [Ethereum client](http://ethdocs.org/en/latest/ethereum-clients/choosing-a-client.html). 
Obviously, it will also work with partially synced clients but you'll not be able to pull recent blocks.

Also make sure to start your client with [RPC enabled](https://github.com/ethereum/wiki/wiki/JSON-RPC#json-rpc-endpoint),
which can be done differently depending on the client you are using. If you use `geth` then you can start your client
like this:
 
```
geth --rpc --rpcaddr 127.0.0.1 --rpcport 8545
```

## Documentation

### Configuration

The following list enumerates all configuration parameters of the `blockchain` input:

 * `protocol`: the underlying blockchain protocol: `bitcoin` (default) or `ethereum`
 * `host`: the host or ip of the bitcoin RPC endpoint to bind to (see [Prerequisite](#Prerequisite) above) (default: `localhost`)
 * `port`: the TCP port of the bitcoin RPC endpoint to bind to (see [Prerequisite](#Prerequisite) above) (default: `8332`)
 * `user`: the username for basic authentication to the bitcoin RPC endpoint (see [Prerequisite](#Prerequisite) above)
 * `password`: the password for basic authentication to the bitcoin RPC endpoint (see [Prerequisite](#Prerequisite) above)
 * `start_height`: (optional) the height of the first block to fetch (default: `0`, i.e. starts at the genesis block)
 * `granularity`: (optional) the granularity of the events to produce (possible values are `block`, `transaction`) (default: `block`) 
   * `block`: one event will be created for each retrieved block
   * `transaction`: one event will be created for each transaction of each retrieved block
   * `event`: one event will be created for each event of a certain contract in all retrieved block
 * `interval`: set how frequently blocks should be retrieved:
   * `1` means retrieve one block per second
   * `0` means retrieve the next block immediately
 * `contract_name`: set the contract to listen for events (MyContract.json must be put in root directory)
 * `event_name`: set the Ethereum event to listen to (plugin will get types in abi)
 * `network_id`: set the contract network id for listening to contract event

### Sample configurations

The following configuration will start pulling block `100000` from the Ethereum blockchain and create one event for each transaction with the retrieved blocks: 
```
input {
  blockchain {
    protocol => "ethereum"
    host => "localhost"
    port => 8545
    start_height => 100000
    granularity => "transaction"
  }
}
output {
  stdout {
    codec => json
  }
}
```

The following configuration depends on a factory architecture ("contract" granularity).
"MyContract" emits events. The first field of every events is the deployee address.
Logstash will get all infos from deployee address thanks to its abi.
```
input {
  blockchain {
    protocol => "ethereum"
    host => "localhost"
    port => 8545
    granularity => "contract"
    contract_name => "MyContract"
    event_name => ["MyEvent1", "MyEvent2]"
    network_id => 1
  }
}
output {
  stdout {
    codec => json
  }
}
```

### Sample Ethereum events

Here is a how a sample Ethereum `block` event will look like:

```
{
  "@timestamp": "2015-08-17T08:15:53.000Z",
  "@version": "1",
  "timestamp": 1439799353,
  "number": 100014,
  "hash": "660cc186e2c5386fdecd98a65fd87ab132c5d64c181b7375323b90567a011fe8",
  "logsBloom": "0",
  "totalDifficulty": 169479946288717920,
  "receiptsRoot": "d988c84f68a0eec17e038d15883c4cff0577a8cd766e7d59156a6ebc2234596d",
  "tx_count": 1,
  "extraData": "476574682f76312e302e312f77696e646f77732f676f312e342e32",
  "nonce": "7a7798c8d78b985b",
  "miner": "8b454d830fef179e66206840f8f3d1d83bc32b17",
  "difficulty": 3853051700593,
  "gasLimit": 3141592,
  "gasUsed": 21000,
  "uncles": [],
  "sha3Uncles": "1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
  "size": 658,
  "transactionsRoot": "761dfca816db7eb8e1c76b332ab692ee198af989ffd0b33a96a7a455fbde0f37",
  "stateRoot": "d1ab073392d6c161f77e9f0dd1a84136ca82c1d66d891d5ef730f031cdc5af9",
  "mixHash": "5688e9d618d1464fbd2c51ff085b17530c189c5c84291435c4ba1e6d96bc5479",
  "parentHash": "3ffbb968107fca6052ff609b6a8478ae9b915a88a3a8f406600aab793cf54d20",
  "tx_info": [
    {
      "blockHash": "660cc186e2c5386fdecd98a65fd87ab132c5d64c181b7375323b90567a011fe8",
      "transactionIndex": 0,
      "nonce": 157,
      "input": "0",
      "r": "cc4386a09f05b2b798fa8a4eee869d35a3298e12aa6599bfadad6828ce3a7338",
      "s": "ca85d381477bcae6fd253161515aeeb104b8fc31e9ad9cb1b9bdeb78784f8f",
      "v": "1b",
      "blockNumber": 100014,
      "gas": 90000,
      "from": "7f7f58d3eb5b7510a301ecc749fc1fcddbe14d",
      "to": "b1abce2918e21ddb93aa452731a12672a3d9f75a",
      "value": 5000000000000000000,
      "hash": "9e5c90e71421b732e5984f6baddab2e9de977147730707cc10a48eaa73fbfcf3",
      "gasPrice": 60347544134
    }
  ]
}
```

And here is a how a sample Ethereum `transaction` event will look like (note that the block information is inside the `block` property):

```
{
  "@timestamp": "2015-08-17T08:15:42.000Z",
  "@version": "1",
  "hash": "870cc7d27296419c9cf8f02a4c4c9a5dc7513a5d82c698d5026873d70fb0cc9d",
  "blockHash": "3ffbb968107fca6052ff609b6a8478ae9b915a88a3a8f406600aab793cf54d20",
  "blockNumber": 100013,
  "transactionIndex": 4,
  "nonce": 26,
  "input": "0",
  "r": "abf5727952e36e3f364237398b4e2af910dcc6e3c5ba84c6dbe1143223021b48",
  "s": "3d0ee86a353d7f480b1406b920c79251c393d30fb3fe573a01ff2ac7d63f8435",
  "v": "1c",
  "gas": 90000,
  "from": "cf00a85f3826941e7a25bfcf9aac575d40410852",
  "to": "d9666150a9da92d9108198a4072970805a8b3428",
  "value": 5000000000000000000,
  "gasPrice": 54588778004,
  "block": {
    "logsBloom": "0",
    "totalDifficulty": 169476093237017300,
    "receiptsRoot": "1b26dff83652d5e430c7e459fd8cfa61936ce9afbe4e3e65c185fd9ce0944a6c",
    "tx_count": 5,
    "extraData": "476574682f76312e302e312f77696e646f77732f676f312e342e32",
    "nonce": "af8b8913abb18374",
    "miner": "7f7f58d3eb5b7510a301ecc749fc1fcddbe14d",
    "difficulty": 3851171245884,
    "gasLimit": 3141592,
    "number": 100013,
    "gasUsed": 105000,
    "uncles": [],
    "sha3Uncles": "1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
    "size": 1102,
    "transactionsRoot": "80983f724b8e86a371d6807339ed6de46f3d2aad547f5df4bc4249fa379a493c",
    "stateRoot": "d06a9b2ecbc3b4f6096fbf956e92b955cf367976cec6ed29a682914e0e681ec6",
    "mixHash": "f09e3a5a47e376acbf71899c31dcc16c0d727b2eea59e5d1c00e068c8edb2a11",
    "parentHash": "c5f56dfc80b2ae51fcdc3f585f9b5ee5870ed28af34240dc7033fced51fb2034",
    "hash": "3ffbb968107fca6052ff609b6a8478ae9b915a88a3a8f406600aab793cf54d20",
    "timestamp": 1439799342
  }
}
```

If you watch for the ethereum events of a factory contract then the event will consist of the deployee properties (read from the abi).
If you want a static mapping in ElasticSearch you will have to do it yourself.

```
{
  "@timestamp": "2015-08-17T08:15:42.000Z",
  "@version": "1",
  "reference": "deployee_reference",
  "name": "deployee_name",
  "address": "0x7f7f58d3eb5b7510a301ecc749fc1fcddbe14d",
  "sender": "0x9eEc522FFa63E081a357Bc8023933de101e36fa8"
}
```

## Need Help?

Need help? Try #logstash on freenode IRC or the https://discuss.elastic.co/c/logstash discussion forum.

## Developing

### 1. Plugin Development and Testing

#### 1.1 Code
- To get started, you'll need JRuby with the Bundler gem installed.

- Create a new plugin or clone and existing from the GitHub [logstash-plugins](https://github.com/logstash-plugins) organization. We also provide [example plugins](https://github.com/logstash-plugins?query=example).

- Install dependencies
```sh
bundle install
```

#### 1.2 Smart contracts to listen to

If you want to listen the ethereum events of some factory contract you will have to put the Deployer and the Deployee JSON file in logstash root.

### 2. Running your unpublished Plugin in Logstash

#### 2.1 Run in a local Logstash clone

- Edit Logstash `Gemfile` and add the local plugin path, for example:
```ruby
gem "logstash-input-blockchain", :path => "/your/local/logstash-input-blockchain"
```
- Install plugin
```sh
bin/logstash-plugin install --no-verify
```
- Run Logstash with your plugin
```sh
bin/logstash -f logstash-docdoku.yml
```
At this point any modifications to the plugin code will be applied to this local Logstash setup. After modifying the plugin, simply rerun Logstash.

#### 2.2 Run in an installed Logstash

You can use the same **2.1** method to run your plugin in an installed Logstash by editing its `Gemfile` and pointing the `:path` to your local plugin development directory or you can build the gem and install it using:

- Build your plugin gem
```sh
gem build logstash-input-blockchain.gemspec
```
- Install the plugin from the Logstash home
```sh
bin/logstash-plugin install /your/local/plugin/logstash-input-blockchain.gem
```
- Start Logstash and proceed to test the plugin

## Contributing

All contributions are welcome: ideas, patches, documentation, bug reports, complaints, and even something you drew up on a napkin.

Programming is not a required skill. Whatever you've seen about open source and maintainers or community members  saying "send patches or die" - you will not see that here.

It is more important to the community that you are able to contribute.

For more information about contributing, see the [CONTRIBUTING](https://github.com/elastic/logstash/blob/master/CONTRIBUTING.md) file.
