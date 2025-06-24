;; Transparent Voting Smart Contract
;; Provides full transparency and auditability for all voting activities

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-POLL-NOT-FOUND (err u101))
(define-constant ERR-POLL-ENDED (err u102))
(define-constant ERR-ALREADY-VOTED (err u103))
(define-constant ERR-INVALID-OPTION (err u104))
(define-constant ERR-POLL-ACTIVE (err u105))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Poll structure
(define-map polls
  { poll-id: uint }
  {
    title: (string-ascii 256),
    description: (string-ascii 1024),
    creator: principal,
    start-block: uint,
    end-block: uint,
    options: (list 10 (string-ascii 128)),
    total-votes: uint,
    is-active: bool,
    created-at: uint
  }
)

;; Vote records - stores individual votes for complete transparency
(define-map votes
  { poll-id: uint, voter: principal }
  {
    option-index: uint,
    option-text: (string-ascii 128),
    voted-at: uint,
    block-height: uint
  }
)

;; Vote counts per option
(define-map vote-counts
  { poll-id: uint, option-index: uint }
  { count: uint }
)

;; Voter participation tracking
(define-map voter-participation
  { poll-id: uint, voter: principal }
  { has-voted: bool }
)

;; Poll audit trail - tracks all poll lifecycle events
(define-map poll-events
  { poll-id: uint, event-index: uint }
  {
    event-type: (string-ascii 32),
    actor: principal,
    timestamp: uint,
    block-height: uint,
    details: (string-ascii 256)
  }
)

;; Global counters
(define-data-var next-poll-id uint u1)
(define-data-var total-polls-created uint u0)
(define-data-var total-votes-cast uint u0)

;; Event index tracker for audit trail
(define-map poll-event-count { poll-id: uint } { count: uint })

;; Create a new poll
(define-public (create-poll 
  (title (string-ascii 256))
  (description (string-ascii 1024))
  (options (list 10 (string-ascii 128)))
  (duration-blocks uint))
  (let
    (
      (poll-id (var-get next-poll-id))
      (start-block stacks-block-height)
      (end-block (+ stacks-block-height duration-blocks))
    )
    (map-set polls
      { poll-id: poll-id }
      {
        title: title,
        description: description,
        creator: tx-sender,
        start-block: start-block,
        end-block: end-block,
        options: options,
        total-votes: u0,
        is-active: true,
        created-at: stacks-block-height
      }
    )
    
    
    ;; Update counters
    (var-set next-poll-id (+ poll-id u1))
    (var-set total-polls-created (+ (var-get total-polls-created) u1))
    
    (ok poll-id)
  )
)

;; Helper function to initialize vote counts
(define-private (initialize-vote-count (option-index uint) (poll-id uint))
  (map-set vote-counts
    { poll-id: poll-id, option-index: option-index }
    { count: u0 }
  )
)

;; Cast a vote
(define-public (cast-vote (poll-id uint) (option-index uint))
  (let
    (
      (poll-data (unwrap! (map-get? polls { poll-id: poll-id }) ERR-POLL-NOT-FOUND))
      (has-voted (default-to false 
                    (get has-voted 
                         (map-get? voter-participation 
                                  { poll-id: poll-id, voter: tx-sender }))))
      (option-text (unwrap! (element-at (get options poll-data) option-index) 
                           ERR-INVALID-OPTION))
      (current-count (get count 
                         (default-to { count: u0 }
                                    (map-get? vote-counts 
                                             { poll-id: poll-id, option-index: option-index }))))
    )
    
    ;; Validation checks
    (asserts! (get is-active poll-data) ERR-POLL-ENDED)
    (asserts! (<= stacks-block-height (get end-block poll-data)) ERR-POLL-ENDED)
    (asserts! (not has-voted) ERR-ALREADY-VOTED)
    (asserts! (< option-index (len (get options poll-data))) ERR-INVALID-OPTION)
    
    ;; Record the vote
    (map-set votes
      { poll-id: poll-id, voter: tx-sender }
      {
        option-index: option-index,
        option-text: option-text,
        voted-at: stacks-block-height,
        block-height: stacks-block-height
      }
    )
    
    ;; Mark voter as having participated
    (map-set voter-participation
      { poll-id: poll-id, voter: tx-sender }
      { has-voted: true }
    )
    
    ;; Update vote count for the option
    (map-set vote-counts
      { poll-id: poll-id, option-index: option-index }
      { count: (+ current-count u1) }
    )
    
    ;; Update total votes for the poll
    (map-set polls
      { poll-id: poll-id }
      (merge poll-data { total-votes: (+ (get total-votes poll-data) u1) })
    )
    
    ;; Record vote event
    (record-poll-event poll-id 
                      (+ (get-event-count poll-id) u1)
                      "VOTE_CAST" 
                      tx-sender
                      (concat "Vote cast for option: " option-text))
    
    ;; Update global vote counter
    (var-set total-votes-cast (+ (var-get total-votes-cast) u1))
    
    (ok true)
  )
)

;; End a poll (only creator or contract owner can end)
(define-public (end-poll (poll-id uint))
  (let
    (
      (poll-data (unwrap! (map-get? polls { poll-id: poll-id }) ERR-POLL-NOT-FOUND))
    )
    (asserts! (or (is-eq tx-sender (get creator poll-data))
                 (is-eq tx-sender CONTRACT-OWNER)) 
             ERR-NOT-AUTHORIZED)
    (asserts! (get is-active poll-data) ERR-POLL-ENDED)
    
    ;; Deactivate the poll
    (map-set polls
      { poll-id: poll-id }
      (merge poll-data { is-active: false })
    )
    
    ;; Record poll end event
    (record-poll-event poll-id 
                      (+ (get-event-count poll-id) u1)
                      "POLL_ENDED" 
                      tx-sender
                      "Poll manually ended")
    
    (ok true)
  )
)

;; Helper function to record poll events
(define-private (record-poll-event 
  (poll-id uint) 
  (event-index uint)
  (event-type (string-ascii 32))
  (actor principal)
  (details (string-ascii 256)))
  (begin
    (map-set poll-events
      { poll-id: poll-id, event-index: event-index }
      {
        event-type: event-type,
        actor: actor,
        timestamp: stacks-block-height,
        block-height: stacks-block-height,
        details: details
      }
    )
    (map-set poll-event-count
      { poll-id: poll-id }
      { count: event-index }
    )
  )
)

;; Helper function to get event count
(define-private (get-event-count (poll-id uint))
  (get count (default-to { count: u0 } 
                        (map-get? poll-event-count { poll-id: poll-id })))
)

;; === AUDIT AND TRANSPARENCY FUNCTIONS ===

;; Get poll information
(define-read-only (get-poll (poll-id uint))
  (map-get? polls { poll-id: poll-id })
)

;; Get vote details for a specific voter
(define-read-only (get-vote (poll-id uint) (voter principal))
  (map-get? votes { poll-id: poll-id, voter: voter })
)

;; Get vote count for a specific option
(define-read-only (get-vote-count (poll-id uint) (option-index uint))
  (map-get? vote-counts { poll-id: poll-id, option-index: option-index })
)

;; Check if a voter has participated in a poll
(define-read-only (has-voter-participated (poll-id uint) (voter principal))
  (default-to false 
             (get has-voted 
                  (map-get? voter-participation { poll-id: poll-id, voter: voter })))
)


;; Helper function for get-all-vote-counts
(define-private (get-option-count (option-index uint) (poll-id uint))
  (get count (default-to { count: u0 } 
                        (map-get? vote-counts { poll-id: poll-id, option-index: option-index })))
)

;; Get poll event from audit trail
(define-read-only (get-poll-event (poll-id uint) (event-index uint))
  (map-get? poll-events { poll-id: poll-id, event-index: event-index })
)

;; Get total number of events for a poll
(define-read-only (get-poll-event-count (poll-id uint))
  (get-event-count poll-id)
)

;; Global statistics for transparency
(define-read-only (get-global-stats)
  {
    total-polls: (var-get total-polls-created),
    total-votes: (var-get total-votes-cast),
    next-poll-id: (var-get next-poll-id),
    current-block: stacks-block-height
  }
)

;; Check if poll is currently active
(define-read-only (is-poll-active (poll-id uint))
  (match (map-get? polls { poll-id: poll-id })
    poll-data
      (and (get is-active poll-data)
           (<= stacks-block-height (get end-block poll-data)))
    false
  )
)

;; ;; Get comprehensive audit information for a poll
;; (define-read-only (get-audit-summary (poll-id uint))
;;   (let
;;     (
;;       (poll-data (map-get? polls { poll-id: poll-id }))
;;     )
;;     (match poll-data
;;       poll-info
;;         {
;;           poll-info: poll-info,
;;           vote-counts: (get-all-vote-counts poll-id),
;;           total-events: (get-event-count poll-id),
;;           is-active: (is-poll-active poll-id),
;;           audit-timestamp: block-height
;;         }
;;       none
;;     )
;;   )
;; )