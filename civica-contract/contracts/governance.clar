;; Decentralized Governance Smart Contract
;; Handles proposal creation, voting, and execution

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u101))
(define-constant ERR-PROPOSAL-EXPIRED (err u102))
(define-constant ERR-PROPOSAL-NOT-ACTIVE (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-INSUFFICIENT-BALANCE (err u105))
(define-constant ERR-PROPOSAL-NOT-PASSED (err u106))
(define-constant ERR-PROPOSAL-ALREADY-EXECUTED (err u107))
(define-constant ERR-INVALID-PARAMETERS (err u108))

;; Data Variables
(define-data-var proposal-counter uint u0)
(define-data-var min-proposal-threshold uint u1000000) ;; 1 STX minimum to create proposal
(define-data-var voting-period uint u1008) ;; ~1 week in blocks (assuming 10min blocks)
(define-data-var quorum-percentage uint u20) ;; 20% quorum required
(define-data-var approval-threshold uint u51) ;; 51% approval required
(define-data-var total-voting-power uint u0)

;; Proposal Status
(define-constant PROPOSAL-ACTIVE u1)
(define-constant PROPOSAL-PASSED u2)
(define-constant PROPOSAL-FAILED u3)
(define-constant PROPOSAL-EXECUTED u4)

;; Data Maps
(define-map proposals
  { proposal-id: uint }
  {
    proposer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    start-block: uint,
    end-block: uint,
    yes-votes: uint,
    no-votes: uint,
    status: uint,
    execution-data: (optional (buff 2048))
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  { vote: bool, voting-power: uint }
)

(define-map voting-power
  { address: principal }
  { power: uint }
)

(define-map governance-members
  { address: principal }
  { is-member: bool, joined-at: uint }
)

;; Read-only functions

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-voting-power (address principal))
  (default-to u0 (get power (map-get? voting-power { address: address })))
)

(define-read-only (get-proposal-counter)
  (var-get proposal-counter)
)

(define-read-only (get-governance-parameters)
  {
    min-proposal-threshold: (var-get min-proposal-threshold),
    voting-period: (var-get voting-period),
    quorum-percentage: (var-get quorum-percentage),
    approval-threshold: (var-get approval-threshold),
    total-voting-power: (var-get total-voting-power)
  }
)

(define-read-only (is-governance-member (address principal))
  (default-to false (get is-member (map-get? governance-members { address: address })))
)

(define-read-only (calculate-proposal-result (proposal-id uint))
  (match (map-get? proposals { proposal-id: proposal-id })
    proposal
    (let
      (
        (yes-votes (get yes-votes proposal))
        (no-votes (get no-votes proposal))
        (total-votes (+ yes-votes no-votes))
        (total-power (var-get total-voting-power))
        (quorum-required (/ (* total-power (var-get quorum-percentage)) u100))
        (approval-required (/ (* total-votes (var-get approval-threshold)) u100))
      )
      {
        yes-votes: yes-votes,
        no-votes: no-votes,
        total-votes: total-votes,
        quorum-met: (>= total-votes quorum-required),
        approval-met: (>= yes-votes approval-required),
        passed: (and (>= total-votes quorum-required) (>= yes-votes approval-required))
      }
    )
    { yes-votes: u0, no-votes: u0, total-votes: u0, quorum-met: false, approval-met: false, passed: false }
  )
)

;; Public functions

(define-public (join-governance)
  (let
    (
      (caller tx-sender)
      (current-balance (stx-get-balance caller))
    )
    (asserts! (>= current-balance (var-get min-proposal-threshold)) ERR-INSUFFICIENT-BALANCE)
    (map-set governance-members
      { address: caller }
      { is-member: true, joined-at: stacks-block-height }
    )
    (map-set voting-power
      { address: caller }
      { power: current-balance }
    )
    (var-set total-voting-power (+ (var-get total-voting-power) current-balance))
    (ok true)
  )
)

(define-public (create-proposal 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (execution-data (optional (buff 2048)))
)
  (let
    (
      (caller tx-sender)
      (caller-balance (stx-get-balance caller))
      (proposal-id (+ (var-get proposal-counter) u1))
      (start-block stacks-block-height)
      (end-block (+ stacks-block-height (var-get voting-period)))
    )
    (asserts! (is-governance-member caller) ERR-UNAUTHORIZED)
    (asserts! (>= caller-balance (var-get min-proposal-threshold)) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> (len title) u0) ERR-INVALID-PARAMETERS)
    (asserts! (> (len description) u0) ERR-INVALID-PARAMETERS)
    
    (map-set proposals
      { proposal-id: proposal-id }
      {
        proposer: caller,
        title: title,
        description: description,
        start-block: start-block,
        end-block: end-block,
        yes-votes: u0,
        no-votes: u0,
        status: PROPOSAL-ACTIVE,
        execution-data: execution-data
      }
    )
    (var-set proposal-counter proposal-id)
    (ok proposal-id)
  )
)

(define-public (vote-on-proposal (proposal-id uint) (vote-yes bool))
  (let
    (
      (caller tx-sender)
      (voter-power (get-voting-power caller))
    )
    (asserts! (is-governance-member caller) ERR-UNAUTHORIZED)
    (asserts! (> voter-power u0) ERR-INSUFFICIENT-BALANCE)
    (asserts! (is-none (map-get? votes { proposal-id: proposal-id, voter: caller })) ERR-ALREADY-VOTED)
    
    (match (map-get? proposals { proposal-id: proposal-id })
      proposal
      (begin
        (asserts! (is-eq (get status proposal) PROPOSAL-ACTIVE) ERR-PROPOSAL-NOT-ACTIVE)
        (asserts! (<= stacks-block-height (get end-block proposal)) ERR-PROPOSAL-EXPIRED)
        
        (map-set votes
          { proposal-id: proposal-id, voter: caller }
          { vote: vote-yes, voting-power: voter-power }
        )
        
        (map-set proposals
          { proposal-id: proposal-id }
          (merge proposal
            (if vote-yes
              { yes-votes: (+ (get yes-votes proposal) voter-power), no-votes: (get no-votes proposal) }
              { yes-votes: (get yes-votes proposal), no-votes: (+ (get no-votes proposal) voter-power) }
            )
          )
        )
        (ok true)
      )
      ERR-PROPOSAL-NOT-FOUND
    )
  )
)

(define-public (finalize-proposal (proposal-id uint))
  (match (map-get? proposals { proposal-id: proposal-id })
    proposal
    (let
      (
        (result (calculate-proposal-result proposal-id))
        (new-status (if (get passed result) PROPOSAL-PASSED PROPOSAL-FAILED))
      )
      (asserts! (is-eq (get status proposal) PROPOSAL-ACTIVE) ERR-PROPOSAL-NOT-ACTIVE)
      (asserts! (> stacks-block-height (get end-block proposal)) ERR-PROPOSAL-EXPIRED)
      
      (map-set proposals
        { proposal-id: proposal-id }
        (merge proposal { status: new-status })
      )
      (ok new-status)
    )
    ERR-PROPOSAL-NOT-FOUND
  )
)

(define-public (execute-proposal (proposal-id uint))
  (match (map-get? proposals { proposal-id: proposal-id })
    proposal
    (begin
      (asserts! (is-eq (get status proposal) PROPOSAL-PASSED) ERR-PROPOSAL-NOT-PASSED)
      
      ;; Mark as executed
      (map-set proposals
        { proposal-id: proposal-id }
        (merge proposal { status: PROPOSAL-EXECUTED })
      )
      
      ;; Here you would implement the actual execution logic
      ;; This could involve calling other contracts, updating parameters, etc.
      ;; For now, we'll just emit an event-like response
      
      (print {
        event: "proposal-executed",
        proposal-id: proposal-id,
        execution-data: (get execution-data proposal)
      })
      
      (ok true)
    )
    ERR-PROPOSAL-NOT-FOUND
  )
)

;; Admin functions (only contract owner)

(define-public (update-governance-parameters
  (new-min-threshold (optional uint))
  (new-voting-period (optional uint))
  (new-quorum-percentage (optional uint))
  (new-approval-threshold (optional uint))
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    
    (match new-min-threshold threshold (var-set min-proposal-threshold threshold) true)
    (match new-voting-period period (var-set voting-period period) true)
    (match new-quorum-percentage quorum 
      (begin
        (asserts! (<= quorum u100) ERR-INVALID-PARAMETERS)
        (var-set quorum-percentage quorum)
      ) 
      true
    )
    (match new-approval-threshold approval 
      (begin
        (asserts! (and (<= approval u100) (> approval u50)) ERR-INVALID-PARAMETERS)
        (var-set approval-threshold approval)
      ) 
      true
    )
    
    (ok true)
  )
)

(define-public (emergency-pause-proposal (proposal-id uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    
    (match (map-get? proposals { proposal-id: proposal-id })
      proposal
      (begin
        (map-set proposals
          { proposal-id: proposal-id }
          (merge proposal { status: PROPOSAL-FAILED })
        )
        (ok true)
      )
      ERR-PROPOSAL-NOT-FOUND
    )
  )
)

;; Initialize contract
(begin
  (map-set governance-members
    { address: CONTRACT-OWNER }
    { is-member: true, joined-at: stacks-block-height }
  )
  (map-set voting-power
    { address: CONTRACT-OWNER }
    { power: u10000000 } ;; 10 STX initial voting power
  )
  (var-set total-voting-power u10000000)
)