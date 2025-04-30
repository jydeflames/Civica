
;; title: vote-counter
;; version:
;; summary:
;; description:

;; Define the data maps for storing votes and candidate information
(define-map votes principal (string-ascii 50))
(define-map vote-counts (string-ascii 50) uint)
(define-data-var total-votes uint u0)

;; Define a list of valid candidates
(define-data-var candidates (list 10 (string-ascii 50)) (list))

;; Function to initialize candidates
(define-public (initialize-candidates (new-candidates (list 10 (string-ascii 50))))
  (begin
    (asserts! (is-eq (var-get candidates) (list)) (err u"Candidates already initialized"))
    (var-set candidates new-candidates)
    (ok true)))

;; Function to cast a vote
(define-public (cast-vote (candidate (string-ascii 50)))
  (begin
    (asserts! (is-some (index-of (var-get candidates) candidate)) (err u"Invalid candidate"))
    (asserts! (is-none (map-get? votes tx-sender)) (err u"Already voted"))
    (map-set votes tx-sender candidate)
    (map-set vote-counts candidate (+ (default-to u0 (map-get? vote-counts candidate)) u1))
    (var-set total-votes (+ (var-get total-votes) u1))
    (ok true)))

;; Read-only function to get the vote count for a specific candidate
(define-read-only (get-candidate-votes (candidate (string-ascii 50)))
  (default-to u0 (map-get? vote-counts candidate)))

;; Read-only function to get the total number of votes
(define-read-only (get-total-votes)
  (var-get total-votes))

;; Read-only function to get the list of candidates
(define-read-only (get-candidates)
  (var-get candidates))

;; Read-only function to check if an address has voted
(define-read-only (has-voted (address principal))
  (is-some (map-get? votes address)))

;; Read-only function to get the candidate an address voted for
(define-read-only (get-vote (address principal))
  (map-get? votes address))