## Oraclize Melonport Module: Pricefeed

This repository contains the source code of a *price feed smart contract* designed to interact as a module for the [Melonport](https://melonport.com)'s Melon protocol.

The contract is now **live** on [Kovan](https://github.com/kovan-testnet/proposal): https://kovan.etherscan.io/address/0x514b75a3caf51a2d6f95add42dd9423dd46ab16b

Thanks to the abstraction provided by Oraclize, this contract supports any exchange providing the relevant data via Web APIs.
In its current form, it is continuosly fetching data from Bitfinex, Kraken, TheRockTrading and Poloniex to provide on-chain references of the BTC, EUR and REP exchange rates against ETH.

Prices are being updated every 5 minutes and, in order to get full transparency, the average price for each asset is securely computed on-chain.

The [authenticity proofs](http://docs.oraclize.it/#authenticity-proofs) attached to each transaction can be used to verify at the any time that the data sent on-chain was authentic.

The contract was designed by following the template interface proposed by the Melonport team, so that its compatibility with the Melon protocol is guaranteed.
The native on-chain interoperability of the Oraclize and Melon protocols makes it trivial for the two systems to cooperate with each other.
