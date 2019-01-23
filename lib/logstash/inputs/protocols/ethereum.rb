# encoding: utf-8
require 'logstash/inputs/protocols/protocol'
require 'date'
require 'ethereum.rb/lib/ethereum/decoder'
require 'ethereum.rb/lib/ethereum/abi'
require "sha3-pure-ruby"

require 'ethereum.rb/lib/ethereum/encoder'

class EthereumProtocol < BlockchainProtocol

  BLOCK_NUM_KEYS = %w(number difficulty totalDifficulty size gasLimit gasUsed timestamp)
  TX_NUM_KEYS = %w(nonce blockNumber transactionIndex gasPrice gas)
  
  DEPLOYEES_INFOS_STRINGS = %w(reference name position creationDate description)
  
  @@decoder = Ethereum::Decoder.new

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
    
    return nil, nil, nil if block_data == nil

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
  public
  def get_event_data(contract_address, event_signature, event_types, tx_hash)
    event_data = Hash.new
    tx_receipt = make_rpc_call('eth_getTransactionReceipt', hexprefix(tx_hash))
    tx_receipt['logs'].each { |logs|
      if logs['address'] == hexprefix(contract_address) && logs['topics'].include?(hexprefix(event_signature))
        # this is my event on my contract !
        tx_data = logs['data']
        # decode the data thanks to the ethereum library
         cpt = 0
         event_types.each { |name, type|
           event_data[name] = decode_data(type, tx_data, cpt)
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
  end
  
  def hexprefix(param)
    return '0x' + param.to_s
  end
  
  def get_tx_receipt(tx_hash)
    make_rpc_call('eth_getTransactionReceipt', hexprefix(tx_hash))
  end
  
def keccak256(string)
  Digest::SHA3.hexdigest(string, 256)
end
  
  # We should probably use the file rather than an hard-coded array
  def get_deployee_infos(deployee_address)
    infos = Hash.new
    DEPLOYEES_INFOS_STRINGS.each { |property|
      infos[property] = get_property("string", property, deployee_address)
    }
    infos
  end
  
  def get_function_return(function_label, contract_address, arguments, return_type)
    input_data = function_label + '('
    input_data_args = ""
    arguments.each { |arg_type, arg_value|
      input_data += arg_type + ','
      arg_tmp = ""
      if arg_type == "address"
        arg_tmp = arg_value.to_s
        while arg_tmp.length != 64 do
          arg_tmp += '0'
        end
      end
      input_data_args += arg_tmp
    }
    input_data = input_data.chop()
    input_data += ')'
    input_data = '0x' + keccak256(input_data)
    input_data = input_data[0, 10]
    input_data += input_data_args
    result = make_rpc_call('eth_call', {"to" => hexprefix(contract_address), "data" => input_data}, "latest")
    decode_data(return_type, result)
  end
  
  def get_property(property_type, property_name, contract_address)
    function_signature = '0x' + keccak256(property_name + '()')
    input_data = function_signature[0, 10]
    result = make_rpc_call('eth_call', {"to" => hexprefix(contract_address), "data" => input_data}, "latest")
    decode_data(property_type, result)
  end
  
  def decode_data(data_type, data, data_start = 0)
    @@decoder.decode(data_type, data, data_start)
  end
  

  

  

end

class String
  def to_decimal
    self.convert_base(16, 10)
  end

  def to_string
    length_before = self.length
    conv = self.convert_base(16, 16)
    while length_before == 66 && conv.length != 64 do
      conv = '0' + conv
    end
    conv
  end

  def convert_base(from, to)
    conv = self.to_i(from).to_s(to)
    to == 10 && conv.to_i <= 9223372036854775807 ? conv.to_i : conv
  end
end
