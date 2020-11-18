# xhalflife-base

## xHalfLifeLinear: Linear Decaying Money Stream Protocol

xHalfLifeLinear has 4 parameters for money streaming:

-   recipient The address towards which the money is streamed.
-   depositAmount The amount of money to be streamed.
-   startBlock stream start block
-   stopBlock stream end block

xHalfLifeLinear is inspired by Sablier Protocol. 

## xHalfLife: Exponentially Decaying Money Stream Protocol

xHalfLife Protocol has 4 parameters for execution: $NumStart$、$K$、$ratio$ and $eps$. Under this protocol, users' reward are split to 2 parts: 

$\text{Deferred Income}$ and $\text{Earned Income}$.

Any new income enters $\text{Deferred Income}$ account.

After $NumStart$ ethereum mainnet block, each time the block number can be divided by $K$, and asset in $\text{Deferred Income}$ balance is over $eps$, $ratio \cdot \text{Deferred Income}$ in $\text{Deferred Income}$ balance will be forwarded into $\text{Earned Income}$ account. 

When needed, any asset in $\text{Earned Income}$ is free to withdraw.

$50\%$ of any single cashflow under xHalfLife is free to withdraw after 

$$-K / log_2(1-ratio) * 13.1s$$

since time at Ethereum Mainnet Block Height $numStart$.

## Money Stream Templates

We wish the templates of money stream can become one of backbone standard in crypto financing world.

For more detail, refer to yellowpaper of xHalfLife and xVote.

For xDEX token farmed from XDEX voting pool, ordinary farming pools, and founder teams' fund, any income is rewarded through xHalfLife protocol. 
