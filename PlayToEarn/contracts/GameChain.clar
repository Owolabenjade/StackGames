;; Play-to-Earn Gaming Platform Smart Contract
;; This contract manages tokens, player achievements, leaderboards, and in-game asset trading.

;; Define the fungible token for the platform
(define-fungible-token platform-token u1000000) ;; Total supply of 1,000,000 units

;; Define contract constants and variables
(define-data-var owner-address principal tx-sender) ;; Initialize with the deployer's address
(define-data-var tokens-held uint u0)
(define-data-var contract-paused bool false)

;; Define maps to manage players, achievements, leaderboard, and assets
(define-map players 
    {player-id: principal} 
    {total-earned: uint, achievements: uint})

(define-map roles 
    {user: principal, role: (string-ascii 128)} 
    {is-assigned: bool})

(define-map leaderboard 
    {player-id: principal} 
    {score: uint})

(define-map time-locked-balances 
    {owner: principal} 
    {unlock-time: uint, amount: uint})

(define-map pending-transactions 
    {sender: principal} 
    {amount: uint, recipient: principal, deadline: uint})

(define-map assets 
    {asset-id: uint} 
    {owner: principal, value: uint})

;; Event Logging Function
(define-private (log-event (action (string-ascii 128)) (details (string-ascii 2048)))
    (print {action: action, details: details}))

;; Helper function to check if the sender is the owner
(define-private (is-owner)
    (is-eq tx-sender (var-get owner-address)))

;; Helper function to check if a user has a specific role
(define-private (has-role (user principal) (role (string-ascii 128)))
    (default-to 
        false
        (get is-assigned (map-get? roles {user: user, role: role}))))

;; Adds a role to a user
(define-public (assign-role (user principal) (role (string-ascii 128)))
    (begin
        (asserts! (is-owner) (err u10))
        (asserts! (< (len role) u129) (err u11)) ;; Check role length
        (asserts! (is-valid-principal user) (err u12)) ;; Check if user is a valid principal
        (map-set roles {user: user, role: role} {is-assigned: true})
        (ok "Role assigned successfully")))

;; Function to mint tokens for the platform
(define-public (mint-tokens (amount uint))
    (begin
        (asserts! (is-owner) (err u100)) ;; Only owner can mint
        (asserts! (< amount u1000000) (err u101)) ;; Limit minting amount
        (ft-mint? platform-token amount tx-sender)))

;; Transfer tokens from one user to another
(define-public (transfer (amount uint) (recipient principal))
    (begin
        (asserts! (is-valid-principal recipient) (err u102)) ;; Check if recipient is a valid principal
        (ft-transfer? platform-token amount tx-sender recipient)))

;; Register a new player
(define-public (register-player (player-id principal))
    (begin
        (asserts! (is-valid-principal player-id) (err u103)) ;; Check if player-id is a valid principal
        (asserts! (is-none (map-get? players {player-id: player-id})) (err u104)) ;; Ensure player isn't already registered
        (map-set players {player-id: player-id} {total-earned: u0, achievements: u0})
        (ok "Player registered successfully")))

;; Update player achievements and rewards
(define-public (update-achievements (player-id principal) (achievement-points uint) (reward-tokens uint))
    (begin
        (asserts! (is-valid-principal player-id) (err u105)) ;; Check if player-id is a valid principal
        (asserts! (<= achievement-points u1000) (err u106)) ;; Limit achievement points
        (asserts! (<= reward-tokens u10000) (err u107)) ;; Limit reward tokens
        (match (map-get? players {player-id: player-id})
            player-data 
                (let (
                    (total (get total-earned player-data))
                    (ach (get achievements player-data)))
                    (begin
                        ;; Update player data
                        (map-set players {player-id: player-id} {total-earned: (+ total reward-tokens), achievements: (+ ach achievement-points)})
                        ;; Transfer reward tokens to player
                        (match (ft-transfer? platform-token reward-tokens (var-get owner-address) player-id)
                            success (ok "Achievements updated successfully")
                            error (err u108))))
            (err u109)))) ;; Player not registered

;; Update the leaderboard with player score
(define-public (update-leaderboard (player-id principal) (score uint))
    (begin
        (asserts! (is-valid-principal player-id) (err u110)) ;; Check if player-id is a valid principal
        (asserts! (<= score u1000000) (err u111)) ;; Limit score
        (ok (map-set leaderboard {player-id: player-id} {score: score}))))

;; Custom function to retrieve the leaderboard entry for a single player
(define-read-only (get-leaderboard-entry (player-id principal))
    (default-to 
        {score: u0} 
        (map-get? leaderboard {player-id: player-id})))

;; Function to retrieve leaderboard entries for multiple players
(define-public (get-multiple-leaderboard-entries (player-ids (list 10 principal)))
    (ok (fold build-leaderboard-entry player-ids (list))))

;; Helper function to build a single leaderboard entry
(define-private (build-leaderboard-entry 
    (player-id principal) 
    (acc (list 10 {player-id: principal, score: uint})))
    (let ((entry (get-leaderboard-entry player-id)))
        (unwrap-panic (as-max-len? 
            (append acc {player-id: player-id, score: (get score entry)})
            u10))))

;; List an asset for trading
(define-public (list-asset (asset-id uint) (value uint))
    (begin
        (asserts! (< asset-id u1000000) (err u112)) ;; Limit asset ID
        (asserts! (<= value u1000000) (err u113)) ;; Limit asset value
        (map-set assets {asset-id: asset-id} {owner: tx-sender, value: value})
        (ok "Asset listed for trading")))

;; Trade asset with another player
(define-public (trade-asset (asset-id uint) (buyer principal))
    (begin
        (asserts! (< asset-id u1000000) (err u114)) ;; Limit asset ID
        (asserts! (is-valid-principal buyer) (err u115)) ;; Check if buyer is a valid principal
        (match (map-get? assets {asset-id: asset-id})
            asset-data
                (let ((owner (get owner asset-data))
                      (value (get value asset-data)))
                    (begin
                        (asserts! (is-eq tx-sender owner) (err u116)) ;; Ensure only the owner can trade
                        (match (ft-transfer? platform-token value buyer owner)
                            success (begin
                                (map-set assets {asset-id: asset-id} {owner: buyer, value: value}) ;; Update ownership
                                (ok "Asset traded successfully"))
                            error (err u117))))
            (err u118)))) ;; Asset not found