;; Liquid Democracy Smart Contract
;; Supports delegation chains, partial delegation, and dynamic re-delegation

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-DELEGATION (err u101))
(define-constant ERR-CIRCULAR-DELEGATION (err u102))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u103))
(define-constant ERR-VOTING-ENDED (err u104))
(define-constant ERR-ALREADY-VOTED (err u105))
(define-constant ERR-INSUFFICIENT-VOTING-POWER (err u106))
(define-constant ERR-DELEGATION-NOT-FOUND (err u107))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Data structures

;; Proposals
(define-map proposals
  { proposal-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    creator: principal,
    start-block: uint,
    end-block: uint,
    yes-votes: uint,
    no-votes: uint,
    total-votes: uint
  }
)

;; Voter registration and voting power
(define-map voters
  { voter: principal }
  {
    voting-power: uint,
    is-active: bool
  }
)

;; Direct delegations: voter -> delegate
(define-map delegations
  { voter: principal, proposal-id: uint }
  {
    delegate: principal,
    voting-power-delegated: uint,
    block-height: uint
  }
)

;; Global delegations (applies to all future proposals unless overridden)
(define-map global-delegations
  { voter: principal }
  {
    delegate: principal,
    voting-power-delegated: uint,
    block-height: uint
  }
)

;; Track votes cast
(define-map votes-cast
  { voter: principal, proposal-id: uint }
  {
    vote: bool, ;; true for yes, false for no
    voting-power-used: uint,
    block-height: uint
  }
)

;; Track received delegated power
(define-map received-delegations
  { delegate: principal, proposal-id: uint }
  {
    total-delegated-power: uint
  }
)

;; Counters
(define-data-var proposal-counter uint u0)

;; Helper functions

;; Get voter's base voting power
(define-read-only (get-voter-power (voter principal))
  (default-to u0 
    (get voting-power 
      (map-get? voters { voter: voter }))))

;; Check if voter is active
(define-read-only (is-voter-active (voter principal))
  (default-to false 
    (get is-active 
      (map-get? voters { voter: voter }))))

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id }))

;; Check if proposal is active
(define-read-only (is-proposal-active (proposal-id uint))
  (match (get-proposal proposal-id)
    proposal-data 
      (and 
        (>= stacks-block-height (get start-block proposal-data))
        (<= stacks-block-height (get end-block proposal-data)))
    false))

;; Get delegation for a specific proposal
(define-read-only (get-delegation (voter principal) (proposal-id uint))
  (map-get? delegations { voter: voter, proposal-id: proposal-id }))

;; Get global delegation
(define-read-only (get-global-delegation (voter principal))
  (map-get? global-delegations { voter: voter }))

;; Get effective delegation (proposal-specific overrides global)
(define-read-only (get-effective-delegation (voter principal) (proposal-id uint))
  (match (get-delegation voter proposal-id)
    specific-delegation (some specific-delegation)
    (get-global-delegation voter)))

;; Calculate available voting power for a voter on a proposal
(define-read-only (get-available-voting-power (voter principal) (proposal-id uint))
  (let (
    (base-power (get-voter-power voter))
    (delegated-power 
      (match (get-effective-delegation voter proposal-id)
        delegation (get voting-power-delegated delegation)
        u0))
    (received-power 
      (default-to u0 
        (get total-delegated-power 
          (map-get? received-delegations { delegate: voter, proposal-id: proposal-id }))))
  )
    (+ (- base-power delegated-power) received-power)))



;; Alternative non-recursive approach (more gas efficient)
(define-read-only (get-final-delegate (voter principal) (proposal-id uint))
  (let (
    (delegation-1 (get-effective-delegation voter proposal-id))
  )
    (match delegation-1
      del-1
        (let ((delegate-1 (get delegate del-1)))
          (if (is-eq delegate-1 voter)
            (err ERR-CIRCULAR-DELEGATION)
            (let ((delegation-2 (get-effective-delegation delegate-1 proposal-id)))
              (match delegation-2
                del-2
                  (let ((delegate-2 (get delegate del-2)))
                    (if (is-eq delegate-2 voter)
                      (err ERR-CIRCULAR-DELEGATION)
                      (let ((delegation-3 (get-effective-delegation delegate-2 proposal-id)))
                        (match delegation-3
                          del-3
                            (let ((delegate-3 (get delegate del-3)))
                              (if (or (is-eq delegate-3 voter) (is-eq delegate-3 delegate-1))
                                (err ERR-CIRCULAR-DELEGATION)
                                (ok delegate-3))) ;; Stop at 3 levels for gas efficiency
                          (ok delegate-2)))))
                (ok delegate-1)))))
      (ok voter))))

;; Admin functions

;; Register a voter
(define-public (register-voter (voter principal) (voting-power uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set voters 
      { voter: voter }
      { voting-power: voting-power, is-active: true }))))

;; Deactivate a voter
(define-public (deactivate-voter (voter principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set voters 
      { voter: voter }
      { voting-power: (get-voter-power voter), is-active: false }))))

;; Create a proposal
(define-public (create-proposal 
  (title (string-ascii 100)) 
  (description (string-ascii 500))
  (duration-blocks uint))
  (let (
    (proposal-id (+ (var-get proposal-counter) u1))
    (start-block stacks-block-height)
    (end-block (+ stacks-block-height duration-blocks))
  )
    (asserts! (is-voter-active tx-sender) ERR-NOT-AUTHORIZED)
    (map-set proposals
      { proposal-id: proposal-id }
      {
        title: title,
        description: description,
        creator: tx-sender,
        start-block: start-block,
        end-block: end-block,
        yes-votes: u0,
        no-votes: u0,
        total-votes: u0
      })
    (var-set proposal-counter proposal-id)
    (ok proposal-id)))

;; Delegation functions

;; Set global delegation (applies to all future proposals)
(define-public (set-global-delegation (delegate principal) (voting-power-to-delegate uint))
  (let (
    (voter-power (get-voter-power tx-sender))
  )
    (asserts! (is-voter-active tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-voter-active delegate) ERR-INVALID-DELEGATION)
    (asserts! (not (is-eq tx-sender delegate)) ERR-INVALID-DELEGATION)
    (asserts! (<= voting-power-to-delegate voter-power) ERR-INSUFFICIENT-VOTING-POWER)
    
    (ok (map-set global-delegations
      { voter: tx-sender }
      {
        delegate: delegate,
        voting-power-delegated: voting-power-to-delegate,
        block-height: stacks-block-height
      }))))

;; Set proposal-specific delegation
(define-public (set-proposal-delegation 
  (proposal-id uint) 
  (delegate principal) 
  (voting-power-to-delegate uint))
  (let (
    (voter-power (get-voter-power tx-sender))
  )
    (asserts! (is-voter-active tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-voter-active delegate) ERR-INVALID-DELEGATION)
    (asserts! (not (is-eq tx-sender delegate)) ERR-INVALID-DELEGATION)
    (asserts! (<= voting-power-to-delegate voter-power) ERR-INSUFFICIENT-VOTING-POWER)
    (asserts! (is-some (get-proposal proposal-id)) ERR-PROPOSAL-NOT-FOUND)
    
    ;; Update delegation
    (map-set delegations
      { voter: tx-sender, proposal-id: proposal-id }
      {
        delegate: delegate,
        voting-power-delegated: voting-power-to-delegate,
        block-height: stacks-block-height
      })
    
    ;; Update received delegations for the delegate
    (let (
      (current-received 
        (default-to u0 
          (get total-delegated-power 
            (map-get? received-delegations { delegate: delegate, proposal-id: proposal-id }))))
    )
      (map-set received-delegations
        { delegate: delegate, proposal-id: proposal-id }
        { total-delegated-power: (+ current-received voting-power-to-delegate) }))
    
    (ok true)))

;; Withdraw global delegation
(define-public (withdraw-global-delegation)
  (begin
    (asserts! (is-some (get-global-delegation tx-sender)) ERR-DELEGATION-NOT-FOUND)
    (ok (map-delete global-delegations { voter: tx-sender }))))

;; Withdraw proposal-specific delegation
(define-public (withdraw-proposal-delegation (proposal-id uint))
  (let (
    (delegation-data (get-delegation tx-sender proposal-id))
  )
    (asserts! (is-some delegation-data) ERR-DELEGATION-NOT-FOUND)
    (asserts! (is-some (get-proposal proposal-id)) ERR-PROPOSAL-NOT-FOUND)
    
    ;; Remove delegation
    (map-delete delegations { voter: tx-sender, proposal-id: proposal-id })
    
    ;; Update received delegations for the former delegate
    (match delegation-data
      delegation
        (let (
          (delegate (get delegate delegation))
          (delegated-power (get voting-power-delegated delegation))
          (current-received 
            (default-to u0 
              (get total-delegated-power 
                (map-get? received-delegations { delegate: delegate, proposal-id: proposal-id }))))
        )
          (if (> current-received delegated-power)
            (map-set received-delegations
              { delegate: delegate, proposal-id: proposal-id }
              { total-delegated-power: (- current-received delegated-power) })
            (map-delete received-delegations { delegate: delegate, proposal-id: proposal-id })))
      true)
    
    (ok true)))

;; Voting functions

;; Cast vote (follows delegation chain if applicable)
(define-public (vote (proposal-id uint) (vote-choice bool) (voting-power-to-use uint))
  (let (
    (available-power (get-available-voting-power tx-sender proposal-id))
  )
    (asserts! (is-voter-active tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-proposal-active proposal-id) ERR-VOTING-ENDED)
    (asserts! (is-none (map-get? votes-cast { voter: tx-sender, proposal-id: proposal-id })) ERR-ALREADY-VOTED)
    (asserts! (<= voting-power-to-use available-power) ERR-INSUFFICIENT-VOTING-POWER)
    
    ;; Record the vote
    (map-set votes-cast
      { voter: tx-sender, proposal-id: proposal-id }
      {
        vote: vote-choice,
        voting-power-used: voting-power-to-use,
        block-height: stacks-block-height
      })
    
    ;; Update proposal vote counts
    (match (get-proposal proposal-id)
      proposal-data
        (let (
          (new-yes-votes (if vote-choice 
            (+ (get yes-votes proposal-data) voting-power-to-use)
            (get yes-votes proposal-data)))
          (new-no-votes (if vote-choice 
            (get no-votes proposal-data)
            (+ (get no-votes proposal-data) voting-power-to-use)))
          (new-total-votes (+ (get total-votes proposal-data) voting-power-to-use))
        )
          (map-set proposals
            { proposal-id: proposal-id }
            (merge proposal-data {
              yes-votes: new-yes-votes,
              no-votes: new-no-votes,
              total-votes: new-total-votes
            })))
      false)
    
    (ok true)))

;; Read-only functions for querying

;; Get proposal results
(define-read-only (get-proposal-results (proposal-id uint))
  (match (get-proposal proposal-id)
    proposal-data
      (ok {
        proposal-id: proposal-id,
        title: (get title proposal-data),
        yes-votes: (get yes-votes proposal-data),
        no-votes: (get no-votes proposal-data),
        total-votes: (get total-votes proposal-data),
        is-active: (is-proposal-active proposal-id)
      })
    ERR-PROPOSAL-NOT-FOUND))

;; Get voter's delegation status
(define-read-only (get-voter-delegation-status (voter principal) (proposal-id uint))
  (ok {
    base-voting-power: (get-voter-power voter),
    global-delegation: (get-global-delegation voter),
    proposal-delegation: (get-delegation voter proposal-id),
    effective-delegation: (get-effective-delegation voter proposal-id),
    available-voting-power: (get-available-voting-power voter proposal-id),
    received-delegated-power: (default-to u0 
      (get total-delegated-power 
        (map-get? received-delegations { delegate: voter, proposal-id: proposal-id })))
  }))

