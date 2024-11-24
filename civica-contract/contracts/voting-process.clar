
;; title: Voting Process Contract
;; version: 1.0
;; summary: This contract manages a decentralized voting process. It allows voters to register, cast votes, and view candidate information. The contract ensures that each registered voter can only vote once, and it tracks the number of votes for each candidate. Admins can register voters, add candidates, and close the voting process. 
;; description: 
;; The Voting Process Contract is a smart contract built for managing a secure and transparent voting system. Voters can register, cast votes for candidates, and retrieve information about their registration status, votes, and candidates. The contract ensures fair voting by preventing double voting and ensuring that only registered voters can participate. Admins can control the election process by registering voters, adding candidates, and closing the voting window.


;; Define constants
(define-constant ERR-NOT-REGISTERED (err u1))
(define-constant ERR-NOT-AUTHORIZED (err u5))
(define-constant ERR-CANDIDATE-EXISTS (err u6))
(define-constant ERR-ALREADY-VOTED (err u2))
(define-constant ERR-INVALID-CANDIDATE (err u3))
(define-constant ERR-VOTING-CLOSED (err u4))

;; Define data maps
(define-map Voters
    principal
    {
        registered: bool,
        has-voted: bool,
        vote-choice: (optional uint)
    }
)

(define-map Candidates
    uint
    {
        name: (string-ascii 50),
        votes: uint
    }
)

;; Define data variables
(define-data-var voting-open bool true)
(define-data-var total-votes uint u0)

;; Read-only functions
(define-read-only (get-voter-info (voter principal))
    (default-to
        {
            registered: false,
            has-voted: false,
            vote-choice: none
        }
        (map-get? Voters voter)
    )
)

(define-read-only (get-candidate-info (candidate-id uint))
    (map-get? Candidates candidate-id)
)

(define-read-only (is-registered (voter principal))
    (get registered (get-voter-info voter))
)

(define-read-only (has-voted (voter principal))
    (get has-voted (get-voter-info voter))
)

;; Public functions
(define-public (cast-vote (candidate-id uint))
    (let (
        (voter tx-sender)
        (voter-info (get-voter-info voter))
    )
        (asserts! (var-get voting-open) ERR-VOTING-CLOSED)
        (asserts! (is-registered voter) ERR-NOT-REGISTERED)
        (asserts! (not (has-voted voter)) ERR-ALREADY-VOTED)
        (asserts! (is-some (get-candidate-info candidate-id)) ERR-INVALID-CANDIDATE)
        
        ;; Update voter information
        (map-set Voters 
            voter
            {
                registered: true,
                has-voted: true,
                vote-choice: (some candidate-id)
            }
        )
        
        ;; Update candidate vote count
        (match (get-candidate-info candidate-id)
            candidate-data (begin
                (map-set Candidates
                    candidate-id
                    {
                        name: (get name candidate-data),
                        votes: (+ u1 (get votes candidate-data))
                    }
                )
                (var-set total-votes (+ (var-get total-votes) u1))
                (ok true)
            )
            ERR-INVALID-CANDIDATE
        )
    )
)

;; Admin functions
(define-public (register-voter (voter principal))
    (begin
        (asserts! (is-eq tx-sender (as-contract tx-sender)) ERR-NOT-AUTHORIZED)
        (map-set Voters 
            voter
            {
                registered: true,
                has-voted: false,
                vote-choice: none
            }
        )
        (ok true)
    )
)

(define-public (add-candidate (candidate-id uint) (name (string-ascii 50)))
    (begin
        (asserts! (is-eq tx-sender (as-contract tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (is-none (get-candidate-info candidate-id)) ERR-CANDIDATE-EXISTS)
        (map-set Candidates
            candidate-id
            {
                name: name,
                votes: u0
            }
        )
        (ok true)
    )
)

(define-public (close-voting)
    (begin
        (asserts! (is-eq tx-sender (as-contract tx-sender)) ERR-NOT-AUTHORIZED)
        (var-set voting-open false)
        (ok true)
    )
)