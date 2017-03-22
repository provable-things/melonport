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
    // Token addresses on Kovan
    address public constant ETHER_TOKEN = 0xc5f550c78db2ee33e5867c432e175cac89073772;
    address public constant BITCOIN_TOKEN = 0x23bb1f93c168a290f0626ec9b9fd8ba8c8591752;
    address public constant REP_TOKEN = 0x02a2656ad55e07c3bc7b5d388e80d5a675b28a20;
    address public constant EURO_TOKEN = 0x605832d1f474cafc26951287ec47d5c09334f1ce;
    address public constant MELON_TOKEN = 0xfcf98c25129ba729e1822e56ffbd3e758b81ce7c;

    // Fields that are only changed in constructor
    /// Note: By definition the price of the base asset against itself (base asset) is always equals one
    address baseAsset; // Is the base asset of a portfolio against which all other assets are priced against

    // Fields that can be changed by functions
    uint frequency = 300; // Frequency of updates in seconds
    uint validity = 600; // After time has passed data is considered invalid.
    mapping(uint => address) public assetsIndex;
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

    function getBaseAsset() constant returns (address) { return baseAsset; }
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
        baseAsset = ETHER_TOKEN; // All input (quote-) prices against this base asset
        addAsset(BITCOIN_TOKEN);
        addAsset(REP_TOKEN);
        addAsset(EURO_TOKEN);
        addAsset(MELON_TOKEN);
        setQuery("[identity] ${[URL] json(https://api.kraken.com/0/public/Ticker?pair=ETHXBT).result.XETHXXBT.c.0}~${[URL] json(https://poloniex.com/public?command=returnTicker).BTC_ETH.last }~${[URL] json(https://api.bitfinex.com/v1/pubticker/ethbtc).last_price} ~||${[URL] json(https://api.kraken.com/0/public/Ticker?pair=XREPXETH).result.XREPXETH.c.0}~${[URL] json(https://poloniex.com/public?command=returnTicker).ETH_REP.last }~||${[URL] json(https://api.kraken.com/0/public/Ticker?pair=ETHEUR).result.XETHZEUR.c.0}~${[URL] json(https://www.therocktrading.com/api/ticker/ETHEUR).result.0.last}~||${[URL] json(https://api.kraken.com/0/public/Ticker?pair=MLNETH).result.XMLNXETH.c.0}~||");
        enableContinuousDelivery();
        updatePriceOraclize();
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
            data[ofAssets[i]] = Data({
                timestamp: now,
                price: newPrices[i],
            });
            PriceUpdated(ofAssets[i], now, newPrices[i]);
        }
    }

    // NON-CONSTANT METHODS

    function __callback(bytes32 oraclizeId, string result, bytes proof) only_oraclize {
        var s = result.toSlice();
        var delimAssets = "||".toSlice();
        var delimPrices = "~".toSlice();
        var assets = new string[](s.count(delimAssets));

        for (uint i = 0; i < assets.length; i++) {
            assets[i] = s.split(delimAssets).toString();
            var assetSlice = assets[i].toSlice();
            address assetAddress = assetsIndex[i+1];
            Asset currentAsset = Asset(assetAddress);
            uint length = assetSlice.count(delimPrices);
            uint decimals = currentAsset.getDecimals();
            uint sum = 0;

            for(uint j = 0; j < length; j++) {
                sum += parseInt(assetSlice.split(delimPrices).toString(), decimals);
            }

            uint price = sum/length;
            data[assetAddress] = Data(now, price);

            PriceUpdated(assetAddress, now, price);
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
        bytes32 oraclizeId = oraclize_query(frequency, 'nested', oraclizeQuery, 350000);
    }

    function setFrequency(uint newFrequency) only_owner {
        if (frequency > validity) throw;
        frequency = newFrequency;
    }

    function setValidity(uint _validity) only_owner {
        validity = _validity;
    }

    function addAsset(address _newAsset) only_owner {
        numAssets += 1;
        assetsIndex[numAssets] = _newAsset;
    }

    function rmAsset(uint _index) only_owner {
        delete assetsIndex[_index];
        numAssets -= 1;
    }

}
