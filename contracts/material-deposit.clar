;; Material Deposit Contract
;; Records recyclable materials submitted by users

;; Data variables
(define-data-var deposit-counter uint u0)
(define-data-var material-type-counter uint u0)
(define-data-var collection-center-counter uint u0)

;; Data maps
(define-map deposits
{ id: uint }
{
  user: principal,
  material-type-id: uint,
  collection-center-id: uint,
  weight: uint,
  timestamp: uint,
  status: (string-ascii 16),
  verification-id: (optional uint),
  notes: (optional (string-ascii 256))
}
)

(define-map material-types
{ id: uint }
{
  name: (string-ascii 32),
  description: (string-ascii 128),
  base-reward-rate: uint,
  unit: (string-ascii 8),
  active: bool
}
)

(define-map collection-centers
{ id: uint }
{
  name: (string-ascii 64),
  location: (string-ascii 128),
  operator: principal,
  active: bool
}
)

(define-map user-totals
{ user: principal, material-type-id: uint }
{
  total-weight: uint,
  total-deposits: uint,
  last-deposit-id: (optional uint)
}
)

(define-map center-operators
{ address: principal }
{ active: bool }
)

(define-map system-admins
{ address: principal }
{ active: bool }
)

;; Initialize contract
(define-public (initialize)
(begin
  (map-set system-admins { address: tx-sender } { active: true })
  (ok true)
)
)

;; Check if address is system admin
(define-read-only (is-system-admin (address principal))
(default-to false (get active (map-get? system-admins { address: address })))
)

;; Check if address is center operator
(define-read-only (is-center-operator (address principal))
(default-to false (get active (map-get? center-operators { address: address })))
)

;; Add a system admin
(define-public (add-system-admin (address principal))
(begin
  ;; Only system admins can add system admins
  (asserts! (is-system-admin tx-sender) (err u403))

  (map-set system-admins
    { address: address }
    { active: true }
  )

  (ok true)
)
)

;; Add a center operator
(define-public (add-center-operator (address principal))
(begin
  ;; Only system admins can add center operators
  (asserts! (is-system-admin tx-sender) (err u403))

  (map-set center-operators
    { address: address }
    { active: true }
  )

  (ok true)
)
)

;; Register a material type
(define-public (register-material-type
  (name (string-ascii 32))
  (description (string-ascii 128))
  (base-reward-rate uint)
  (unit (string-ascii 8)))
(let ((new-id (+ (var-get material-type-counter) u1)))
  ;; Only system admins can register material types
  (asserts! (is-system-admin tx-sender) (err u403))

  ;; Update counter
  (var-set material-type-counter new-id)

  ;; Store material type data
  (map-set material-types
    { id: new-id }
    {
      name: name,
      description: description,
      base-reward-rate: base-reward-rate,
      unit: unit,
      active: true
    }
  )

  (ok new-id)
)
)

;; Register a collection center
(define-public (register-collection-center
  (name (string-ascii 64))
  (location (string-ascii 128))
  (operator principal))
(let ((new-id (+ (var-get collection-center-counter) u1)))
  ;; Only system admins can register collection centers
  (asserts! (is-system-admin tx-sender) (err u403))

  ;; Operator must be a registered center operator
  (asserts! (is-center-operator operator) (err u403))

  ;; Update counter
  (var-set collection-center-counter new-id)

  ;; Store collection center data
  (map-set collection-centers
    { id: new-id }
    {
      name: name,
      location: location,
      operator: operator,
      active: true
    }
  )

  (ok new-id)
)
)

;; Record a material deposit
(define-public (record-deposit
  (user principal)
  (material-type-id uint)
  (collection-center-id uint)
  (weight uint)
  (notes (optional (string-ascii 256))))
(let ((new-id (+ (var-get deposit-counter) u1))
      (material-type (map-get? material-types { id: material-type-id }))
      (collection-center (map-get? collection-centers { id: collection-center-id })))

  ;; Only center operators can record deposits
  (asserts! (is-center-operator tx-sender) (err u403))

  ;; Material type and collection center must exist and be active
  (asserts! (and
              (is-some material-type)
              (is-some collection-center)
              (get active (unwrap-panic material-type))
              (get active (unwrap-panic collection-center)))
            (err u404))

  ;; Center operator must be assigned to this collection center
  (asserts! (is-eq tx-sender (get operator (unwrap-panic collection-center))) (err u403))

  ;; Weight must be positive
  (asserts! (> weight u0) (err u400))

  ;; Update counter
  (var-set deposit-counter new-id)

  ;; Store deposit data
  (map-set deposits
    { id: new-id }
    {
      user: user,
      material-type-id: material-type-id,
      collection-center-id: collection-center-id,
      weight: weight,
      timestamp: block-height,
      status: "pending",
      verification-id: none,
      notes: notes
    }
  )

  ;; Update user totals
  (update-user-totals user material-type-id weight new-id)

  (ok new-id)
)
)

;; Update user totals (helper function)
(define-private (update-user-totals (user principal) (material-type-id uint) (weight uint) (deposit-id uint))
(let ((current-totals (default-to
                        { total-weight: u0, total-deposits: u0, last-deposit-id: none }
                        (map-get? user-totals { user: user, material-type-id: material-type-id }))))

  (map-set user-totals
    { user: user, material-type-id: material-type-id }
    {
      total-weight: (+ (get total-weight current-totals) weight),
      total-deposits: (+ (get total-deposits current-totals) u1),
      last-deposit-id: (some deposit-id)
    }
  )
)
)

;; Update deposit status
(define-public (update-deposit-status (deposit-id uint) (status (string-ascii 16)) (verification-id (optional uint)))
(let ((deposit (map-get? deposits { id: deposit-id })))
  ;; Only system admins can update deposit status
  (asserts! (is-system-admin tx-sender) (err u403))

  ;; Deposit must exist
  (asserts! (is-some deposit) (err u404))

  ;; Status must be valid
  (asserts! (or
              (is-eq status "pending")
              (is-eq status "verified")
              (is-eq status "rejected")
              (is-eq status "rewarded"))
            (err u400))

  ;; Store updated deposit
  (map-set deposits
    { id: deposit-id }
    (merge (unwrap-panic deposit) {
      status: status,
      verification-id: verification-id
    })
  )

  (ok true)
)
)

;; Update material type reward rate
(define-public (update-reward-rate (material-type-id uint) (base-reward-rate uint))
(let ((material-type (map-get? material-types { id: material-type-id })))
  ;; Only system admins can update reward rates
  (asserts! (is-system-admin tx-sender) (err u403))

  ;; Material type must exist
  (asserts! (is-some material-type) (err u404))

  ;; Store updated material type
  (map-set material-types
    { id: material-type-id }
    (merge (unwrap-panic material-type) { base-reward-rate: base-reward-rate })
  )

  (ok true)
)
)

;; Get deposit details
(define-read-only (get-deposit (deposit-id uint))
(map-get? deposits { id: deposit-id })
)

;; Get material type details
(define-read-only (get-material-type (material-type-id uint))
(map-get? material-types { id: material-type-id })
)

;; Get collection center details
(define-read-only (get-collection-center (collection-center-id uint))
(map-get? collection-centers { id: collection-center-id })
)

;; Get user totals for a material type
(define-read-only (get-user-totals (user principal) (material-type-id uint))
(default-to
  { total-weight: u0, total-deposits: u0, last-deposit-id: none }
  (map-get? user-totals { user: user, material-type-id: material-type-id })
)
)

;; Get all user deposits
(define-read-only (get-user-deposits (user principal))
;; This is a simplified implementation
;; In a real contract, you would need to iterate through deposits
(filter-deposits-by-user user)
)

;; Helper function to filter deposits by user
;; In a real implementation, this would search through all deposits
(define-read-only (filter-deposits-by-user (user principal))
;; Placeholder implementation
(list)
)

;; Get all deposits for a collection center
(define-read-only (get-center-deposits (collection-center-id uint))
;; This is a simplified implementation
;; In a real contract, you would need to iterate through deposits
(filter-deposits-by-center collection-center-id)
)

;; Helper function to filter deposits by collection center
;; In a real implementation, this would search through all deposits
(define-read-only (filter-deposits-by-center (collection-center-id uint))
;; Placeholder implementation
(list)
)

;; Get all deposits for a material type
(define-read-only (get-material-deposits (material-type-id uint))
;; This is a simplified implementation
;; In a real contract, you would need to iterate through deposits
(filter-deposits-by-material material-type-id)
)

;; Helper function to filter deposits by material type
;; In a real implementation, this would search through all deposits
(define-read-only (filter-deposits-by-material (material-type-id uint))
;; Placeholder implementation
(list)
)

