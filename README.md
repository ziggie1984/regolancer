# Intro

Why even write another rebalancer? Usually, the only motivation is that the
existing software doesn't satisfy the developer. There may be different reasons
why improving the existing programs isn't something the dev wants. Maybe the
language is the problem or architecture. For me there were many reasons
including these. Two most advanced rebalancers for lnd are
[rebalance-lnd](https://github.com/C-Otto/rebalance-lnd) (Python) and
[bos](https://github.com/alexbosworth/balanceofsatoshis) (JS). However, each has
something the other one lacks, both have runtime requirements and both are
_slow_. I decided to fix these issues by rewriting the things I liked in Go
instead so it can be easily compiled and used anywhere. I also made the output
pretty, close to the design of [accumulator's fork of
rebalance-lnd](https://github.com/accumulator/rebalance-lnd).

# Features

- automatically pick source and target channel by local/remote liquidity ratio
- retry indefinitely until it succeeds or 6 hours pass (currently hardcoded)
- payments time out after 5 minutes (currently hardcoded) so if something's
  stuck the process will continue shortly
- JSON config file to set some defaults you prefer
- optional route probing using binary search to rebalance a smaller amount
- data caching to speed up alias resolution, quickly skip failing channel pairs etc.
- sensible node capacity formatting according to [Bitcoin
  design](https://bitcoin.design/guide/designing-products/units-and-symbols/)
  guidelines (easy to tell how many full coins there are)
- automatic max fee calculation from the target channel policy and preferred
  economy fee ratio (the amount spent on rebalanced to the expected income from
  this channel)
- excluding your channels from consideration
- excluding any nodes from routing through (if they're known to be slow or constantly failing to route anything)
- using just one source and/or target channel (by default all imbalanced
  channels are considered and pairs are chosen randomly)

# Parameters

```
  -f, --config=              config file path
  -c, --connect=             connect to lnd using host:port
  -t, --tlscert=             path to tls.cert to connect
      --macaroon-dir=        path to the macaroon directory
      --macaroon-filename=   macaroon filename
  -n, --network=             bitcoin network to use
      --pfrom=               channels with less than this inbound liquidity percentage will be considered as source channels
      --pto=                 channels with less than this outbound liquidity percentage will be considered as target channels
  -p, --perc=                use this value as both pfrom and pto from above
  -a, --amount=              amount to rebalance
      --econ-ratio=          economical ratio for fee limit calculation as a multiple of target channel fee (for example, 0.5 means you want to pay at max half the fee you might earn for routing out of the target channel)
  -b, --probe=               if the payment fails at the last hop try to probe lower amount using binary search
  -i, --exclude-channel-in=  don't use this channel as incoming (can be specified multiple times)
  -o, --exclude-channel-out= don't use this channel as outgoing (can be specified multiple times)
  -e, --exclude-channel=     don't use this channel at all (can be specified multiple times)
  -d, --exclude-node=        don't use this node for routing (can be specified multiple times)
      --to=                  try only this channel as target (should satisfy other constraints too)
      --from=                try only this channel as source (should satisfy other constraints too)
```

Look in `config.json.sample` for corresponding JSON keys, they're not exactly
equivalent. If in doubt, open `main.go` and look at the `var params struct`. If
defined in both config and CLI, the CLI parameters take priority. Connect,
macaroon and tls settings can be omitted if you have a default `lnd`
installation.

# Probing

This is an obscure feature that `bos` uses in rebalances, it relies on protocol
error messages. I didn't read the `bos` source but figured out how to check if
the route can process the requested amount without actually making a payment:
generate a random payment hash and send it. `lnd` will refuse to accept it
(because there's no corresponding invoice) but the program gets a different
error than the usual `TEMPORARY_CHANNEL_FAILURE`. Then we can do a binary search
to estimate the best amount in a few steps. Note, however, that the smallest
amount can be 2<sup>n</sup> times less than you planned to rebalance (where `n`
is the number of steps during probing). For example, 5 steps and 1,000,000 sats
amount mean that you might rebalance at least 1000000/2<sup>5</sup> = 31250 sats
if the probe succeeds. Another problem is that fees can become too high for
smaller amounts because of the base fee that starts dominating the fee
structure. It's handled properly, however.

When enabled, probing starts if the payment fails at the second to last channel.
The last channel comes to yourself so you know it's guaranteed to accept the
specified amount. If all other channels could route this amount, the only
unknown one is that second to last. Then we try different amounts until either a
good amount is found or we run out of steps. If a good amount is learned the
payment is then done along this route and it should succeed. If, for whatever
reason, it doesn't (liquidity shifted somewhere unexpectedly) the cycle
continues.

# What's wrong with the other rebalancers

While I liked probing in `bos`, it has many downsides: gives up quickly on
trivial errors, has very rigid channel selection options (all should be chosen
manually), no automatic fee calculation, cryptic errors, [weird
defaults](https://github.com/alexbosworth/balanceofsatoshis/issues/88) and
[ineffective
design](https://github.com/alexbosworth/balanceofsatoshis/issues/125). It can
also unbalance another channel, there are no safety belts. It might be okay if
you absolutely need one channel to be refilled no matter the cost but if you
want your node to be profitable you have to account for every sat.

Rebalance-lnd is much better for automation but it still can't choose multiple
source and destination channels and try to send between them. You have to select
one source and/or one target, the other side is chosen randomly, often only to
discard a lot of routes because of too high fees (this constraint can be
specified while querying routes but it isn't). The default route limit is 100
so you either have to increase it or restart the script until it succeeds. I
noticed multiple times that it concedes after 20-30 attempts saying there are no
more routes but after restart still finds and tries more. It also lacks probing,
consumes quite a lot of CPU time sometimes and I personally find Python a big
pain to work with.

# Why rebalance at all

I'm still a bit torn on this topic. At some points in time I was a fan of
rebalancing, then I stopped, now I began again. I guess it all comes with
experience. LN is still in its infancy and when the network is widely available
and used on daily basis rebalancing won't be needed. But today we have a lot of
poorly managed nodes (especially the big ones!) with default minimal fees and
more experienced nodes quickly drain this liquidity only to resell it for a
higher price. If a node has hundreds or thousands of channels with zero
liquidity hints it becomes very hard to balance such channels. It essentially
boils down to a bruteforce which is exactly what this program does. It seeks the
network for liquidity that's cheaper than your own and moves it to you.

For now some liquidity can be just dead. Even if you set 0/0 on a full channel
you see no routing through it. Because it's the opposite direction that everyone
wants. So you have to move it manually, getting incoming liquidity to sell for
some other outbound liquidity you have. And when you run out of it you need to
refill the channels using that dead liquidity. In the future, hopefully, the
daily network activity will do this job thanks to circular economy. Today it's
not yet the case.

However, there's not much point in rebalancing all the channels. See which are
empty for weeks and consider them as candidates. From my experience, you might
have a few channels that can be drained very quickly if the fee is too low. They
are channels to exchanges and service providers, sometimes other big nodes that
consume all liquidity you throw at them. That's your source of income,
basically. These channels should be added to exceptions in your config so
they're never used as a source, even when they match the percent limit.

# How to route better

By all means, use [charge-lnd](https://github.com/accumulator/charge-lnd). Your
goal is to minimize local forward failures. It can be achieved with fees and/or
max HTLC parameter. You can try to move the dead liquidity with 0/0 fee before
doing rebalance. You absolutely should discourage routing through empty
channels. Best way is to set max_htlc on them so they're automatically discarded
during route construction. You can also disable them (it only happens on your
end so you'll be able to receive liquidity but not send it) but it hurts your
score on various sites so better not to do it. Increase fees or lower max_htlc and
you'll be good. You can set multiple brackets with multiple limits like:
- 20% local balance => set max_htlc to 0.1 of channel capacity (so it can
  process ≈2 payments max or more smaller payments)
- 10% local balance => set max_htlc to 0.01 of channel capacity (small payments
  can get through but channel won't be drained quickly)
- 1% local balance => set max_htlc to 1 sat essentially disabling it

Same can be done with fees but if you decide to rebalance, watch out: you might
spend a lot on rebalancing if your empty channel sets 5000ppm fee but after it
gets refilled it switches back to regular 50 or 100ppm. You'll never earn that
back. Learn how `charge-lnd` works and write your own rules!

# Goals and future

It's a small weekend project that I did for myself and my own goals. I gladly
accept contributions and suggestions though! For now I implemented almost
everything I needed, maybe except a couple of timeouts being configurable. But I
don't see much need for that as of now. The main goals and motivation for this
project were:
- make it reliable and robust so I don't have to babysit it (stop/restart if it
  hangs, crashes or gives up early)
- make it fast and lightweight, don't stress `lnd` too much as it all should run
  on RPi
- provide many settings for tweaking, every node is different but the incentives
  are the same
- since it's a user-oriented software, make the output pleasant to look at, the
  important bits should be highlighted and easy to read