# Dev Give Test

Use this when you do not have a second player to test the Give Item transfer logic.

## In-game F8 commands

```text
testgive water 5
givetest water 1
showtestreceiver
cleartestreceiver
```

`givetest` removes the item from your character inventory and adds it to a fake container:

```text
owner_type = test_receiver
owner_id = dev_receiver_1
```

This proves the remove/add/audit transfer logic works without needing another player online.

## txAdmin commands

```text
invgivetest <serverId> water 1
invshowtest
invcleartest
```
