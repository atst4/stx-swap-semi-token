(impl-trait .sip013-semi-fungible-token-trait.sip013-semi-fungible-token-trait)
(impl-trait .sip013-transfer-many-trait.sip013-transfer-many-trait)

(define-fungible-token fractional-nft)
(define-non-fungible-token semi-fungible-token-id {token-id: uint, owner: principal})
(define-map token-balances {token-id: uint, owner: principal} uint)
(define-map token-supplies uint uint)

(define-constant contract-owner tx-sender)

(define-constant err-owner-only (err u100))
(define-constant err-unknown-token (err u101))
(define-constant err-cannot-be-zero (err u102))
(define-constant err-token-already-exists (err u102))
(define-constant err-insufficient-balance (err u1))
(define-constant err-invalid-sender (err u4))

(define-private (set-balance (token-id uint) (balance uint) (owner principal))
	(map-set token-balances {token-id: token-id, owner: owner} balance)
)

(define-private (get-balance-uint (token-id uint) (who principal))
	(default-to u0 (map-get? token-balances {token-id: token-id, owner: who}))
)

(define-read-only (get-balance (token-id uint) (who principal))
	(ok (get-balance-uint token-id who))
)

(define-read-only (get-overall-balance (who principal))
	(ok (ft-get-balance fractional-nft who))
)

(define-read-only (get-total-supply (token-id uint))
	(ok (default-to u0 (map-get? token-supplies token-id)))
)

(define-read-only (get-overall-supply)
	(ok (ft-get-supply fractional-nft))
)

(define-read-only (get-decimals (token-id uint))
	(ok u0)
)

(define-read-only (get-token-uri (token-id uint))
	(ok none)
)

(define-public (transfer (token-id uint) (amount uint) (sender principal) (recipient principal))
	(let
		(
			(sender-balance (get-balance-uint token-id sender))
		)
		(asserts! (or (is-eq sender tx-sender) (is-eq sender contract-caller)) err-invalid-sender)
		(asserts! (<= amount sender-balance) err-insufficient-balance)
		(try! (ft-transfer? fractional-nft amount sender recipient))
		(try! (tag-nft-token-id {token-id: token-id, owner: sender}))
		(try! (tag-nft-token-id {token-id: token-id, owner: recipient}))
		(set-balance token-id (- sender-balance amount) sender)
		(set-balance token-id (+ (get-balance-uint token-id recipient) amount) recipient)
		(print {type: "sft_transfer", token-id: token-id, amount: amount, sender: sender, recipient: recipient})
		(ok true)
	)
)

(define-public (transfer-memo (token-id uint) (amount uint) (sender principal) (recipient principal) (memo (buff 34)))
	(begin
		(try! (transfer token-id amount sender recipient))
		(print memo)
		(ok true)
	)
)

(define-private (transfer-many-iter (item {token-id: uint, amount: uint, sender: principal, recipient: principal}) (previous-response (response bool uint)))
	(match previous-response prev-ok (transfer (get token-id item) (get amount item) (get sender item) (get recipient item)) prev-err previous-response)
)

(define-public (transfer-many (transfers (list 200 {token-id: uint, amount: uint, sender: principal, recipient: principal})))
	(fold transfer-many-iter transfers (ok true))
)

(define-private (transfer-many-memo-iter (item {token-id: uint, amount: uint, sender: principal, recipient: principal, memo: (buff 34)}) (previous-response (response bool uint)))
	(match previous-response prev-ok (transfer-memo (get token-id item) (get amount item) (get sender item) (get recipient item) (get memo item)) prev-err previous-response)
)

(define-public (transfer-many-memo (transfers (list 200 {token-id: uint, amount: uint, sender: principal, recipient: principal, memo: (buff 34)})))
	(fold transfer-many-memo-iter transfers (ok true))
)

(define-public (fractionalise (token-id uint) (fractions uint))
	(let
		(
			(sender-balance (get-balance-uint token-id tx-sender))
			(total-supply (default-to u0 (map-get? token-supplies token-id)))
		)
		(asserts! (> total-supply u0) err-unknown-token)
		(asserts! (> fractions u0) err-cannot-be-zero)
		(asserts! (is-eq total-supply sender-balance) err-insufficient-balance)
		(try! (ft-burn? fractional-nft total-supply tx-sender))
		(try! (ft-mint? fractional-nft fractions tx-sender))
		(try! (tag-nft-token-id {token-id: token-id, owner: tx-sender}))
		(set-balance token-id fractions tx-sender)
		(print {type: "sft_burn", token-id: token-id, amount: total-supply, sender: tx-sender})
		(print {type: "sft_mint", token-id: token-id, amount: fractions, recipient: tx-sender})
		(ok true)
	)
)

(define-public (mint (token-id uint) (recipient principal))
	(begin
		(asserts! (is-eq tx-sender contract-owner) err-owner-only)
		(asserts! (is-eq (default-to u0 (map-get? token-supplies token-id)) u0) err-token-already-exists)
		(try! (ft-mint? fractional-nft u1 recipient))
		(try! (tag-nft-token-id {token-id: token-id, owner: recipient}))
		(set-balance token-id (+ (get-balance-uint token-id recipient) u1) recipient)
		(map-set token-supplies token-id (+ (unwrap-panic (get-total-supply token-id)) u1))
		(print {type: "sft_mint", token-id: token-id, amount: u1, recipient: recipient})
		(ok true)
	)
)

(define-private (tag-nft-token-id (nft-token-id {token-id: uint, owner: principal}))
	(begin
		(and
			(is-some (nft-get-owner? semi-fungible-token-id nft-token-id))
			(try! (nft-burn? semi-fungible-token-id nft-token-id (get owner nft-token-id)))
		)
		(nft-mint? semi-fungible-token-id nft-token-id (get owner nft-token-id))
	)
)
