pragma solidity ^0.4.8;

import "github.com/melonproject/protocol/contracts/datafeeds/PriceFeedProtocol.sol";
import "github.com/melonproject/protocol/contracts/assets/Asset.sol";
import "github.com/melonproject/protocol/contracts/dependencies/ERC20.sol";
import "github.com/melonproject/protocol/contracts/dependencies/SafeMath.sol";
import "github.com/melonproject/protocol/contracts/dependencies/Owned.sol";
import "github.com/oraclize/ethereum-api/oraclizeAPI.sol";
import "github.com/Arachnid/solidity-stringutils/strings.sol";

/// @title Price Feed Contract
/// @author Melonport AG <team@melonport.com>
/// @notice Routes external data to smart contracts


contract PriceFeed is usingOraclize, PriceFeedProtocol, SafeMath, Owned {
    using strings for *;
    
    // TYPES
    struct Data {
        uint timestamp; // Timestamp of last price update of this asset
        uint price; // Price of asset relative to Ether with decimals of this asset
    }
    
    // FIELDS

    // Constant fields
    uint frequency = 60; // Frequency of updates in seconds
    uint validity = 120; // After time has passed data is considered invalid.

    // Fields that can be changed by functions
    uint updateCounter = 0; // Used to track how many times data has been updated
    mapping (address => Data) data; // Address of fungible => price of fungible
    // EVENTS

    event PriceUpdated(address ofAsset, uint ofPrice, uint ofUpdateCounter);
    // ORACLIZE DATA-STRUCTURES
    
    mapping (bytes32 => address) id2Asset;
    mapping (address => bool) continuousDelivery;
    mapping (address => string) assetQuery;

    // MODIFIERS

   modifier msg_value_at_least(uint x) {
        assert(msg.value >= x);
        _;
    }

    modifier data_initialised(address ofAsset) {
        assert(data[ofAsset].timestamp > 0);
        _;
    }

    modifier data_still_valid(address ofAsset) {
        assert(now - data[ofAsset].timestamp <= validity);
        _;
    }

    modifier arrays_equal(address[] x, uint[] y) {
        assert(x.length == y.length);
        _;
    }
    
    modifier only_oraclize {
        if (msg.sender != oraclize_cbAddress()) throw;
        _;
    }

    // CONSTANT METHODS
    // CONSTANT METHODS

    function getFrequency() constant returns (uint) { return frequency; }
    function getValidity() constant returns (uint) { return validity; }

    // Pre: Checks for initialisation and inactivity
    // Post: Price of asset, where last updated not longer than `validity` seconds ago
    function getPrice(address ofAsset)
        constant
        data_initialised(ofAsset)
        data_still_valid(ofAsset)
        returns (uint)

    {
        return data[ofAsset].price;
    }

    // Pre: Checks for initialisation and inactivity
    // Post: Timestamp and price of asset, where last updated not longer than `validity` seconds ago
    function getData(address ofAsset)
        constant
        data_initialised(ofAsset)
        data_still_valid(ofAsset)
        returns (uint, uint)
    {
        return (data[ofAsset].timestamp, data[ofAsset].price);
    }

    // NON-CONSTANT METHODS

    function PriceFeed() payable {
        oraclize_setProof(proofType_TLSNotary | proofStorage_IPFS);

         //BTC
        addQuery(0x23bb1f93c168a290f0626ec9b9fd8ba8c8591752, "[identity] ${[URL] json(https://api.kraken.com/0/public/Ticker?pair=ETHXBT).result.XETHXXBT.c.0}~${[URL] json(https://poloniex.com/public?command=returnTicker).BTC_ETH.last }~${[URL] json(https://api.bitfinex.com/v1/pubticker/ethbtc).last_price}~");
        enableContinuousDelivery(0x23bb1f93c168a290f0626ec9b9fd8ba8c8591752);
        updatePriceOraclizeOfAsset(0x23bb1f93c168a290f0626ec9b9fd8ba8c8591752);


         //REP
        addQuery(0x02a2656ad55e07c3bc7b5d388e80d5a675b28a20, "[identity] ${[URL] json(https://api.kraken.com/0/public/Ticker?pair=XREPXETH).result.XREPXETH.c.0}~${[URL] json(https://poloniex.com/public?command=returnTicker).ETH_REP.last }~");
        enableContinuousDelivery(0x02a2656ad55e07c3bc7b5d388e80d5a675b28a20);
        updatePriceOraclizeOfAsset(0x02a2656ad55e07c3bc7b5d388e80d5a675b28a20);


         //EURO
        addQuery(0x605832d1f474cafc26951287ec47d5c09334f1ce, "[identity] ${[URL] json(https://api.kraken.com/0/public/Ticker?pair=ETHEUR).result.XETHZEUR.c.0}~${[URL] json(https://www.therocktrading.com/api/ticker/ETHEUR).result.0.last}~");
        enableContinuousDelivery(0x605832d1f474cafc26951287ec47d5c09334f1ce);
        updatePriceOraclizeOfAsset(0x605832d1f474cafc26951287ec47d5c09334f1ce);
    }
    
    function () payable {}
    
    /// Pre: Only Owner; Same sized input arrays
    /// Post: Update price of asset relative to Ether
    /** Ex:
     *  Let asset == EUR-T, let Value of 1 EUR-T := 1 EUR == 0.080456789 ETH
     *  and let EUR-T decimals == 8,
     *  => data[EUR-T].price = 8045678
     */
    function updatePrice(address[] ofAssets, uint[] newPrices)
        only_owner
        arrays_equal(ofAssets, newPrices)
    {
        for (uint i = 0; i < ofAssets.length; ++i) {
            // Intended to prevent several updates w/in one block, eg w different prices
            assert(data[ofAssets[i]].timestamp != now);
            data[ofAssets[i]] = Data( now, newPrices[i] );
            PriceUpdated(ofAssets[i], now, newPrices[i]);
        }
    }
    // NON-CONSTANT METHODS

     
    function __callback(bytes32 oraclizeId, string result, bytes proof) only_oraclize {
        address currentAddress = id2Asset[oraclizeId];

        var s = result.toSlice();
        var delim = "~".toSlice();
        Asset currentAsset = Asset(currentAddress);
        uint decimals = currentAsset.decimals();
        uint sum = 0;
        uint length = s.count(delim);
        for (uint i = 0; i < length; i++) {
             sum += parseInt(s.split(delim).toString(), decimals);
        }
        
        uint price = sum/length;
        data[currentAddress] = Data(now, price);
        
        if (continuousDelivery[currentAddress]) {
            updatePriceOraclizeOfAsset(currentAddress);
        }
        
        updateCounter += 1;
        PriceUpdated(currentAddress, price, updateCounter);
    }
     
    function addQuery(address ofAsset, string query) only_owner {
        assetQuery[ofAsset] = query;
    }
     
    function rmQuery(address ofAsset) {
        delete assetQuery[ofAsset];
    }
     
     
    function enableContinuousDelivery(address ofAsset) only_owner {
        continuousDelivery[ofAsset] = true;
    }
     
    function disableContinuousDelivery(address ofAsset) only_owner {
        delete continuousDelivery[ofAsset];
    }
     
    function updatePriceOraclizeOfAsset(address ofAsset)
        payable {
        bytes32 oraclizeId = oraclize_query(frequency, 'nested', assetQuery[ofAsset]);
        id2Asset[oraclizeId]= ofAsset;
    }
    
    function setFrequency(uint newFrequency) only_owner {
        frequency = newFrequency;
    }
    
    function updatePriceOraclize(address[] ofAssets)
        only_owner 
        payable {
        
        for (uint i = 0; i < ofAssets.length; ++i) {
           
            if (sha3(assetQuery[ofAssets[i]]) != sha3('')) {
                updatePriceOraclizeOfAsset(ofAssets[i]);
            }            
        }
        
    }
}
