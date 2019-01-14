# encoding: utf-8
require 'logstash/inputs/protocols/protocol'
require 'date'
require 'ethereum.rb/lib/ethereum/decoder'
require 'ethereum.rb/lib/ethereum/abi'
require "sha3-pure-ruby"

class EthereumProtocol < BlockchainProtocol

  BLOCK_NUM_KEYS = %w(number difficulty totalDifficulty size gasLimit gasUsed timestamp)
  TX_NUM_KEYS = %w(nonce blockNumber transactionIndex gasPrice gas)

  def initialize(host, port, user, pass, logger)
    super(host, port, nil, nil, logger)
  end

  # returns a JSON body to be sent to the Ethereum JSON-RPC endpoint
  def get_post_body(name, params)
    { 'method' => name, 'params' => params, 'id' => '1', 'jsonrpc' => '2.0' }
  end

  # returns the latest block number
  public
  def get_block_count
    begin
      make_rpc_call('eth_blockNumber').to_decimal
    rescue JSONRPCError, java.lang.Exception => e
      @logger.warn? && @logger.warn('Could not find latest block count', :exc => e)
    end
  end

  # returns the block at the given height
  public
  def get_block(height)
    # get the block data
    block_data = make_rpc_call('eth_getBlockByNumber', hexprefix(height), true)

    # get all transaction data
    tx_info = block_data.delete('transactions')

    # unhex numbers and strings
    unhex(block_data, BLOCK_NUM_KEYS)
    tx_info.each do |tx|
      unhex(tx, TX_NUM_KEYS)
    end

    timestamp = Time.at(block_data['timestamp']).utc.to_datetime.iso8601(3)

    return block_data, tx_info, timestamp
  end # def get_block
  
  # returns the event decoded data/types
  def get_event_data(contract_address, event_signature, event_types, tx_hash)
    event_data = Hash.new
    tx_receipt = make_rpc_call('eth_getTransactionReceipt', hexprefix(tx_hash))
    tx_receipt['logs'].each { |logs|
      if logs['address'] == contract_address && logs['topics'].include?(hexprefix(event_signature))
        # this is my event on my contract !
        tx_data = logs['data']
        # decode the data thanks to the ethereum library
         cpt = 0
         event_types.each { |name, type|
           event_data[name] = decode_event_data(type, tx_data, cpt)
          cpt += 20
         }
      end
    }
    event_data
  end
  
  def get_signature_from_name_types(event_name, event_types)
    tmp = event_name + '('
    event_types.each { |name, type|
     tmp += type + ','
    }
    tmp.chop() + ')'
  end

  def unhex(data, num_keys)
    data.each do |key, value|
      next if value.nil? or value.kind_of?(Array)

      if num_keys.include? key
           if(value.methods.include? :to_decimal)
                 data[key] = value.to_decimal()
           end
      else
           if(value.methods.include? :to_string)
                 data[key] = value.to_string()
           end
      end
    end
    
    # These are the methods we delegate to a third-party
    # To get the topic of an event we do a keccak256(event_signature)
    # For now it uses keccak-pure-ruby directly
    def get_event_signature(event_name, event_types)
      event_signature = get_signature_from_name_types(event_name, event_types)
      Digest::SHA3.hexdigest(event_signature, 256)
    end
    
    # To decode the event data according to the types of the abi
    def decode_event_data(data_type, data, data_start)
      @decoder = Ethereum::Decoder.new if @decoder == nil
      hexprefix(@decoder.decode(data_type, data, data_start))
    end
  end
  
  def hexprefix(param)
    return '0x' + param.to_s
  end
end

class String
  def to_decimal
    self.convert_base(16, 10)
  end

  def to_string
    self.convert_base(16, 16)
  end

  def convert_base(from, to)
    conv = self.to_i(from).to_s(to)
    to == 10 && conv.to_i <= 9223372036854775807 ? conv.to_i : conv
  end
end
