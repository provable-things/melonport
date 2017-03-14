# Oraclize Melonport PriceFeed

This repository contains the source code of a *price feed smart contract* designed to interact with [Melonport](https://melonport.com).

The contract is now **live** on [Kovan](https://github.com/kovan-testnet/proposal): https://kovan.etherscan.io/address/0x23261f0b78cb52e9b23a981e9373e759405a009f

Thanks to the abstraction provided by Oraclize, this contract supports any exchange providing the relevant data via Web APIs.
In its current form, it is continuosly fetching data from Bitfinex, Kraken, TheRockTrading and Poloniex to provide on-chain references of the BTC, EUR and REP exchange rates against ETH.

Prices are being updated every 5 minutes and, in order to get full transparency, the average price for each asset is securely computed on-chain.

The [authenticity proofs](http://docs.oraclize.it/#authenticity-proofs) attached to each transaction can be used to verify at the any time that the data sent on-chain was authentic.
