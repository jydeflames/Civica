
;; title: voting-window
;; version:
;; summary:
;; description:

;; Voting Window Management Contract
;; This contract manages the voting period with start/end times and ensures immutability after voting ends

;; Define data variables
(define-data-var voting-started bool false)
(define-data-var voting-ended bool false)
(define-data-var start-block uint u0)
(define-data-var end-block uint u0)

;; Map to store votes: (principal -> vote-value)
(define-map votes principal uint)

;; Map to track who has voted
(define-map has-voted principal bool)

;; Total vote count
(define-data-var vote-count uint u0)

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-VOTING-NOT-STARTED (err u101))
(define-constant ERR-VOTING-ENDED (err u102))
(define-constant ERR-ALREADY-VOTED (err u103))
(define-constant ERR-ALREADY-STARTED (err u104))
(define-constant ERR-NOT-ENDED (err u105))

;; Only contract owner can start/end voting
(define-constant CONTRACT-OWNER tx-sender)

;; Function to start the voting period
(define-public (start-voting (duration uint))
  (begin
    ;; Check if caller is authorized
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    ;; Check if voting hasn't already started
    (asserts! (not (var-get voting-started)) ERR-ALREADY-STARTED)
    
    ;; Set the start block to current block height
    (var-set start-block stacks-block-height)
    
    ;; Set the end block based on duration
    (var-set end-block (+ stacks-block-height duration))
    
    ;; Mark voting as started
    (var-set voting-started true)
    
    ;; Return success
    (ok true)))

;; Function to end voting
(define-public (end-voting)
  (begin
    ;; Check if caller is authorized
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    ;; Check if voting has started
    (asserts! (var-get voting-started) ERR-VOTING-NOT-STARTED)
    
    ;; Check if voting hasn't already ended
    (asserts! (not (var-get voting-ended)) ERR-NOT-ENDED)
    
    ;; Mark voting as ended
    (var-set voting-ended true)
    
    ;; Return success
    (ok true)))

;; Function to cast a vote
(define-public (cast-vote (vote-value uint))
  (begin
    ;; Check if voting has started
    (asserts! (var-get voting-started) ERR-VOTING-NOT-STARTED)
    
    ;; Check if voting hasn't ended
    (asserts! (not (var-get voting-ended)) ERR-VOTING-ENDED)
    
    ;; Check if current block is within voting period
    (asserts! (and (>= stacks-block-height (var-get start-block)) 
                  (<= stacks-block-height (var-get end-block)))
              ERR-VOTING-ENDED)
    
    ;; Check if sender hasn't already voted
    (asserts! (is-none (map-get? has-voted tx-sender)) ERR-ALREADY-VOTED)
    
    ;; Record the vote
    (map-set votes tx-sender vote-value)
    
    ;; Mark sender as having voted
    (map-set has-voted tx-sender true)
    
    ;; Increment vote count
    (var-set vote-count (+ (var-get vote-count) u1))
    
    ;; Return success
    (ok true)))

;; Read-only function to check if voting is active
(define-read-only (is-voting-active)
  (and (var-get voting-started)
       (not (var-get voting-ended))
       (>= stacks-block-height (var-get start-block))
       (<= stacks-block-height (var-get end-block))))

;; Read-only function to get voting status
(define-read-only (get-voting-status)
  {
    started: (var-get voting-started),
    ended: (var-get voting-ended),
    start-block: (var-get start-block),
    end-block: (var-get end-block),
    current-block: stacks-block-height,
    vote-count: (var-get vote-count)
  })

;; Read-only function to check if a principal has voted
(define-read-only (has-principal-voted (voter principal))
  (default-to false (map-get? has-voted voter)))

;; Read-only function to get a principal's vote
(define-read-only (get-vote (voter principal))
  (map-get? votes voter))

