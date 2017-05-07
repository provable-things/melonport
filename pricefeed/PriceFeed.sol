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
        uint price; // Price of asset quoted against `quoteAsset` times ten to the power of {decimals of this asset}
    }

    struct strAsset {
        address assetAddress;
        bool invertPair;
    }

    // FIELDS

    // Constant fields
    // Token addresses on Kovan
    address public constant ETHER_TOKEN = 0x7506c7BfED179254265d443856eF9bda19221cD7;
    address public constant MELON_TOKEN = 0x4dffea52b0b4b48c71385ae25de41ce6ad0dd5a7;
    address public constant BITCOIN_TOKEN = 0x9E4C56a633DD64a2662bdfA69dE4FDE33Ce01bdd;
    address public constant REP_TOKEN = 0xF61b8003637E5D5dbB9ca8d799AB54E5082CbdBc;
    address public constant EURO_TOKEN = 0xC151b622fDeD233111155Ec273BFAf2882f13703;

    // Fields that are only changed in constructor
    /// Note: By definition the price of the quote asset against itself (quote asset) is always equals one
    address quoteAsset; // Is the quote asset of a portfolio against which all other assets are priced against

    // Fields that can be changed by functions
    uint frequency = 300; // Frequency of updates in seconds
    uint validity = 600; // Time in seconds data is considered valid
    uint gasLimit = 350000;
    strAsset[] public assetsIndex;
    uint public numAssets = 0;
    mapping (address => Data) data; // Address of fungible => price of fungible

    // EVENTS

    event PriceUpdated(address indexed ofAsset, uint atTimestamp, uint ofPrice);

    // ORACLIZE DATA-STRUCTURES

    bool continuousDelivery;
    string oraclizeQuery;

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

    function getQuoteAsset() constant returns (address) { return quoteAsset; }
    function getFrequency() constant returns (uint) { return frequency; }
    function getValidity() constant returns (uint) { return validity; }

    // Pre: Asset has been initialised
    // Post: Returns boolean if data is valid
    function getStatus(address ofAsset)
        constant
        data_initialised(ofAsset)
        returns (bool)
    {
        return now - data[ofAsset].timestamp <= validity;
    }

    // Pre: Asset has been initialised and is active
    // Post: Price of asset, where last updated not longer than `validity` seconds ago
    function getPrice(address ofAsset)
        constant
        data_initialised(ofAsset)
        data_still_valid(ofAsset)
        returns (uint)
    {
        return data[ofAsset].price;
    }

    // Pre: Asset has been initialised and is active
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
        quoteAsset = ETHER_TOKEN; // Is the quote asset of a portfolio against which all other assets are priced against
        addAsset(MELON_TOKEN, false); // ETH/MLN
        addAsset(BITCOIN_TOKEN, true); // BTC/ETH -> ETH/BTC
        addAsset(EURO_TOKEN, true); // EUR/ETH -> ETH/EUR
        addAsset(REP_TOKEN, false); // ETH/REP
        setQuery("[identity] ${[URL] json(https://api.kraken.com/0/public/Ticker?pair=MLNETH).result.XMLNXETH.c.0}~||${[URL] json(https://api.kraken.com/0/public/Ticker?pair=ETHXBT).result.XETHXXBT.c.0}~${[URL] json(https://poloniex.com/public?command=returnTicker).BTC_ETH.last }~${[URL] json(https://api.bitfinex.com/v1/pubticker/ethbtc).last_price} ~||${[URL] json(https://api.kraken.com/0/public/Ticker?pair=ETHEUR).result.XETHZEUR.c.0}~${[URL] json(https://www.therocktrading.com/api/ticker/ETHEUR).result.0.last}~||${[URL] json(https://api.kraken.com/0/public/Ticker?pair=XREPXETH).result.XREPXETH.c.0}~${[URL] json(https://poloniex.com/public?command=returnTicker).ETH_REP.last }~||");
        enableContinuousDelivery();
        oraclize_query('nested', oraclizeQuery, 500000);
    }

    function () payable {}

    /// Pre: Only Owner; Same sized input arrays
    /// Post: Update price of asset relative to Ether
    /** Ex:
     *  Let quoteAsset == ETH, let asset == EUR-T, let Value of 1 EUR-T := 1 EUR == 0.080456789 ETH
     *  and let EUR-T decimals == 8,
     *  => data[EUR-T].price = 8045678 [ETH/ (EUR-T * 10**8)]
     */
    function updatePrice(address[] ofAssets, uint[] newPrices)
        only_owner
        arrays_equal(ofAssets, newPrices)
    {
        for (uint i = 0; i < ofAssets.length; ++i) {
            // Intended to prevent several updates w/in one block, eg w different prices
            assert(data[ofAssets[i]].timestamp != now);
            data[ofAssets[i]] = Data({
                timestamp: now,
                price: newPrices[i],
            });
            PriceUpdated(ofAssets[i], now, newPrices[i]);
        }
    }

    function __callback(bytes32 oraclizeId, string result, bytes proof) only_oraclize {
        var s = result.toSlice();
        var assets = new string[](s.count("||".toSlice()));

        for (uint i = 0; i < assets.length; i++) {
            assets[i] = s.split("||".toSlice()).toString();
            var assetSlice = assets[i].toSlice();
            strAsset currentAssetStr = assetsIndex[i+1];
            Asset currentAsset = Asset(currentAssetStr.assetAddress);
            Asset baseAsset = Asset(quoteAsset);
            uint length = assetSlice.count("~".toSlice());
            uint copyLength = length;
            uint sum = 0;

            for(uint j = 0; j < length; j++) {
                var part = assetSlice.split("~".toSlice());
                if (!part.empty()) {
                    sum += parseInt(part.toString(), baseAsset.getDecimals());
                }
                else {
                    copyLength -= 1;
                }
            }


            if (sum != 0 && copyLength != 0) {
                uint price = sum/length;

                if (currentAssetStr.invertPair) {
                    price = (10**currentAsset.getDecimals()*10**baseAsset.getDecimals())/price;
                }
                data[currentAssetStr.assetAddress] = Data(now, price);
                PriceUpdated(currentAssetStr.assetAddress, now, price);
            }
        }

        if (continuousDelivery) {
            updatePriceOraclize();
        }
    }

    function setQuery(string query) only_owner {
        oraclizeQuery = query;
    }

    function enableContinuousDelivery() only_owner {
        continuousDelivery = true;
    }

    function disableContinuousDelivery() only_owner {
        delete continuousDelivery;
    }

    function updatePriceOraclize()
        payable {
        oraclize_query(frequency, 'nested', oraclizeQuery, gasLimit);
    }

    function setFrequency(uint newFrequency) only_owner {
        if (frequency > validity) throw;
        frequency = newFrequency;
    }

    function setValidity(uint _validity) only_owner {
        validity = _validity;
    }

    function addAsset(address _newAsset, bool invertPrice) only_owner {
        assetsIndex.push(strAsset(_newAsset, invertPrice));
    }

	
	function rmAsset(address _assetRemoved) only_owner {
         uint length = assetsIndex.length;
         for (uint i = 0; i < length; i++) {
             if (assetsIndex[i].assetAddress == _assetRemoved) {
                 break;
             }
         }
 
        assetsIndex[i] = assetsIndex[assetsIndex.length - 1];
        assetsIndex.length--;
    }
 
    function setGasLimit(uint _newGasLimit) only_owner {
        gasLimit = _newGasLimit;
    }

}
