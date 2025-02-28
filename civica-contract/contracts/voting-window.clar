
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


