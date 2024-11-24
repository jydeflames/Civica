;; title: Voter Registration Contract
;; version: 1.0
;; summary: This contract handles voter registration, eligibility checks, and identity validation for a decentralized voting system. Voters can register based on a whitelist or by staking a minimum amount of tokens. The contract ensures that only eligible voters can participate and prevents duplicate registrations. Admins can manage the whitelist and oversee staking functionality.
;; description: 
;; The Voter Registration Contract is a key component for managing voter eligibility and registration in a decentralized voting system. It allows users to register either by being whitelisted or by staking a predefined minimum amount of tokens. The contract tracks voter eligibility and ensures that only registered, eligible voters can participate in the election process. Admins can add or remove addresses from the whitelist and manage staking functionality. This system enhances the fairness and integrity of the voting process by ensuring that only legitimate participants are able to vote.


;; Data Maps
(define-map Voters
    { address: principal }  ;; key is the voter's address
    {
        registered: bool,   ;; whether the voter has registered
        eligible: bool,     ;; whether the voter is eligible (based on whitelist/tokens)
        stake-amount: uint  ;; amount of tokens staked (if using stake-based eligibility)
    }
)

(define-map Whitelist
    { address: principal }
    { whitelisted: bool }
)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant min-stake-amount u100)  ;; minimum tokens required to be eligible
(define-constant err-not-authorized (err u100))
(define-constant err-already-registered (err u101))
(define-constant err-not-eligible (err u102))
(define-constant err-insufficient-stake (err u103))

;; Read-only functions
(define-read-only (get-voter-info (address principal))
    (default-to
        { registered: false, eligible: false, stake-amount: u0 }
        (map-get? Voters { address: address })
    )
)

(define-read-only (is-whitelisted (address principal))
    (default-to
        false
        (get whitelisted (map-get? Whitelist { address: address }))
    )
)

(define-read-only (is-eligible (address principal))
    (let (
        (voter-info (get-voter-info address))
        (whitelisted (is-whitelisted address))
    )
    (or 
        whitelisted
        (>= (get stake-amount voter-info) min-stake-amount)
    ))
)

;; Public functions
(define-public (register-voter)
    (let (
        (caller tx-sender)
        (voter-info (get-voter-info caller))
    )
    (asserts! (not (get registered voter-info)) err-already-registered)
    (asserts! (is-eligible caller) err-not-eligible)
    
    (ok (map-set Voters
        { address: caller }
        {
            registered: true,
            eligible: true,
            stake-amount: (get stake-amount voter-info)
        }
    )))
)

;; Admin functions
(define-public (add-to-whitelist (address principal))
    (begin
        (asserts! (is-contract-owner tx-sender) err-not-authorized)
        (ok (map-set Whitelist
            { address: address }
            { whitelisted: true }
        ))
    )
)

(define-public (remove-from-whitelist (address principal))
    (begin
        (asserts! (is-contract-owner tx-sender) err-not-authorized)
        (ok (map-set Whitelist
            { address: address }
            { whitelisted: false }
        ))
    )
)

;; Staking functions
(define-public (stake-tokens (amount uint))
    (let (
        (caller tx-sender)
        (voter-info (get-voter-info caller))
    )
    (try! (stx-transfer? amount caller (as-contract tx-sender)))
    (ok (map-set Voters
        { address: caller }
        {
            registered: (get registered voter-info),
            eligible: true,
            stake-amount: (+ (get stake-amount voter-info) amount)
        }
    )))
)

;; Helper functions
(define-private (is-contract-owner (address principal))
    (is-eq address contract-owner)
)