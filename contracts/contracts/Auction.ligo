type bidder is address

type auctionId is nat

type tokenKey is address * nat

type tokenOwner is address

type tx is michelson_pair(address, "to_", michelson_pair(nat, "token_id", nat, "amount"), "")

type txList is list (tx)

type transferBatch is michelson_pair(address, "from_", txList, "txs")

type auction is record [
  quantity : nat;
  owner    : tokenOwner;
  token    : tokenKey;
  bank     : tez; // Банк аукциона
  leader   : bidder;
  leader_percent : nat; // Процент банка, который получит победитель, задается оунером
  // cashback_percent : nat; // Процент кэшбэка проигравшим - пока не будет реализовано
  min_bank    : tez; // Минимальная сумма ставок чтобы аукцион состоялся
  bid_size    : tez; // Фиксированный размер ставки, задается оунером
  bid_timeout : int; // Начальное значение таймаута ставки, задается оунером
  opens_at   : timestamp;
  closes_at  : timestamp;
]

type auctionStarter is record [
  quantity : nat;
  token    : tokenKey;
  leader_percent : nat; // Процент банка, который получит победитель, задается оунером
  min_bid_count : nat; // Минимальное число ставок, задается оунером как минимальное количество ставок, если банк не достаточен, то аукцион не состоялся  
  bid_size       : tez; // Фиксированный размер ставки, задается оунером
  bid_timeout   : int; // Начальное значение таймаута ставки, задается оунером
  opens_at     : timestamp;
]

const housePercent : nat = 1n

const bidStep : tez = 0.2tez

const minPrice : tez = 1tez

type storage is record [
  houseBank : tez;
  houseOwner : address;
  nextId : auctionId;
  auctions : big_map (auctionId, auction);
  bidders  : big_map (auctionId * bidder, tez);
  metadata : big_map (string, bytes);
]

// type startParams is michelson_pair(michelson_pair (address, "fa2contract", nat, "token_id"), "", michelson_pair (nat, "quantity", tez, "start_price" ), "")

type action is
  | Bid    of auctionId
  | Claim  of auctionId
  | Start  of auctionStarter
  | Sweep
  | Withdraw of auctionId


type return is list(operation) * storage

const noop : list(operation) = (nil : list (operation))

function getAuction(const id : auctionId; const s : storage) : auction is
  case s.auctions[id] of
      | None -> (failwith("BAD_ID") : auction) 
      | Some(a) -> a
  end;

function getBidderBalance(const a : auctionId; const b : bidder; const s : storage) : tez is
  case s.bidders[(a, b)] of
      | None -> 0tez 
      | Some(a) -> a
  end;

function transferToken(const from_ : address; const to_ : address; const token : tokenKey; const q : nat; const s : storage) : return is
 begin
    const param : list(transferBatch) = list [(from_, list[(to_, (token.1, q))])];
  
    const fa2 : contract (list(transferBatch)) = case (Tezos.get_entrypoint_opt("%transfer", token.0) : option(contract (list(transferBatch)))) of
      | None -> (failwith("NOT_FA2_CONTRACT") : contract (list(transferBatch)))
      | Some(c) -> c
    end;
 end with (list [Tezos.transaction(param, 0tz, fa2)], s)

function startAuction(const a : auctionStarter; var s : storage) : return is
  begin
    if Tezos.amount > 0tez then failwith("TZ > 0") else skip;

    if a.quantity = 0n then failwith("ZERO_QUANTITY") else skip;

    if a.bid_size = 0tez then failwith("ZERO_BID_SIZE") else skip;

    if a.opens_at < Tezos.now then a.opens_at := Tezos.now else skip;

    if a.leader_percent > 100n then failwith("LEADER_PERCENT > 100") else skip;
    
    if a.bid_timeout <= 0 then failwith("BAD_TIMEOUT") else skip;

    s.auctions[s.nextId] := record [
      quantity = a.quantity;
      owner = Tezos.sender;
      token = a.token;
      bank  = 0tez;
      leader = Tezos.sender;
      leader_percent = a.leader_percent;
      min_bank = a.min_bid_count * a.bid_size;
      bid_size = a.bid_size;
      bid_timeout = a.bid_timeout;
      opens_at = a.opens_at;
      closes_at = a.opens_at + a.bid_timeout;
    ];
    s.nextId := s.nextId + 1n;

  end with transferToken(Tezos.sender, Tezos.self_address, a.token, a.quantity, s)

function bid(const auction_id : auctionId; var s : storage) : return is
  begin
    const auction : auction = getAuction(auction_id, s);

    const bidder : bidder = Tezos.sender;
    // auction owner can't bid also current leader can't rise bid
    if auction.owner = bidder then failwith("BID_DECLINED") else skip;

    if auction.opens_at > Tezos.now then failwith("AUCTION_NOT_OPEN_YET") else skip;

    var closingTime : timestamp := auction.closes_at;

    if closingTime < Tezos.now  then failwith("AUCTION_CLOSED") else skip;

    if Tezos.amount =/= auction.bid_size then failwith("WRONG_BID_AMOUNT") else skip;

    (* effects *)
    const bank = auction.bank + auction.bid_size;

    const bid_count : nat = bank / auction.bid_size;

    const diff : int = auction.bid_timeout / 2;

    const timeout : int = auction.bid_timeout - int(Bitwise.shift_right(abs(diff), bid_count));;

    closingTime := Tezos.now + timeout;

    patch auction with record [
        leader = bidder;
        bank = bank;
        bid_timeout = timeout;
        closes_at = closingTime;
    ];

    const betSum : tez = getBidderBalance(auction_id, bidder, s) + Tezos.amount;

    s.bidders[(auction_id, bidder)] := betSum;
    
    s.auctions[auction_id] := auction;

  end with (noop, s)

function sweepBalance(var s : storage) : return is
  begin
    if Tezos.sender =/= s.houseOwner then failwith("ACCESS_DENIED") else skip;
    const bal : tez = s.houseBank;
    // Tezos.transaction(unit, Amount in mutez, address)
    const tz1 : contract(unit) = case (Tezos.get_contract_opt(Tezos.sender) : option(contract(unit))) of
      | None -> (failwith("NO_CONTRACT") : contract(unit))
      | Some(c) -> c
    end;
    s.houseBank := 0tz;
  end with (list [Tezos.transaction(unit, bal, tz1)], s)

  function withdraw(const auction_id : auctionId; var s : storage) : return is
    begin
        const auction : auction = getAuction(auction_id, s);
        const claimer : bidder = Tezos.sender;
        
        if auction.closes_at > Tezos.now then failwith("AUCTION_IS_OPEN") else skip;
        
        const bal : tez = getBidderBalance(auction_id, claimer, s);

        const succeded : bool = auction.bank >= auction.min_bank;
        
        var share : tez := 0tz;
        const leader_share : tez = auction.bank / 100n * auction.leader_percent;

        (* owner withdraw only when auction succeded *)
        if auction.owner = claimer then block {
            if not succeded then skip else failwith("AUCTION_FAILED");

            if bal > 0tz then failwith("ALREADY_WITHDRAWN") else skip;
            
            share := auction.bank - leader_share;

            s.bidders[(auction_id, claimer)] := share;
        } 
        (* leader may withdraw when auction succeded *)
        else if (auction.leader = claimer) and (succeded) and (leader_share > 0tz) then block {
            
            if bal = 0tz then failwith("ALREADY_WITHDRAWN") else skip;
            
            share := leader_share;

            s.bidders[(auction_id, claimer)] := 0tz;            

        } else block {
            if not succeded then share := bal else skip;
            s.bidders[(auction_id, claimer)] := 0tz;
        };

        const tz1 : contract(unit) = case (Tezos.get_contract_opt(claimer) : option(contract(unit))) of
        | None -> (failwith("NO_CONTRACT") : contract(unit))
        | Some(c) -> c
        end;
    end with (list [Tezos.transaction(unit, share, tz1)], s)

(* Send token to auction leader or owner in case of auction failure *)
function claimReward(const auction_id : auctionId; var s : storage) : return is
  begin
    const claimer : address = Tezos.sender;
    
    var auction : auction := getAuction(auction_id, s);
    
    if auction.closes_at > Tezos.now then failwith("AUCTION_IS_OPEN") else skip;

    if (claimer =/= auction.leader) and (claimer =/= auction.owner) then failwith("ACCESS_DENIED") else skip;

    if auction.quantity = 0n then failwith("CLAIMED_ALREADY") else skip;
    (* owner may claim token if auction failed to collect enough bank*)
    if (claimer = auction.owner) and (auction.bank >= auction.min_bank) then failwith("AUCTION_SUCCEDED") else skip;
    
    if (claimer =/= auction.owner) and (auction.bank < auction.min_bank) then failwith("AUCTION_FAILED") else skip;
    
    (* effects *)
    const quantity : nat = auction.quantity;
    
    auction.quantity := 0n;

    s.auctions[auction_id] := auction;

  end with transferToken(Tezos.self_address, claimer, auction.token, quantity, s)

function main (const action: action; var s : storage) : return is
  case action of
    | Start(p) -> startAuction(p, s)
    | Bid(p)   -> bid(p, s)
    | Claim(p) -> claimReward(p, s)
    | Sweep    -> sweepBalance(s)
    | Withdraw(p) -> withdraw(p, s)
  end
