;; Drought Response Coordination Contract
;; Coordinate community drought response with water restrictions and conservation measures
;; Tracks drought levels, implements restrictions, and manages emergency protocols

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-INVALID-DROUGHT-LEVEL (err u402))
(define-constant ERR-RESTRICTION-NOT-FOUND (err u403))
(define-constant ERR-HOUSEHOLD-NOT-FOUND (err u404))
(define-constant ERR-ALREADY-REPORTED (err u405))
(define-constant ERR-INVALID-ALLOCATION (err u406))
(define-constant ERR-EMERGENCY-NOT-ACTIVE (err u407))

;; Drought levels: 0=Normal, 1=Watch, 2=Warning, 3=Emergency, 4=Exceptional
(define-constant DROUGHT-NORMAL u0)
(define-constant DROUGHT-WATCH u1)
(define-constant DROUGHT-WARNING u2)
(define-constant DROUGHT-EMERGENCY u3)
(define-constant DROUGHT-EXCEPTIONAL u4)

;; Maximum allocation per household during emergencies (in gallons)
(define-constant MAX-EMERGENCY-ALLOCATION u5000)

;; Data Variables
(define-data-var current-drought-level uint DROUGHT-NORMAL)
(define-data-var emergency-protocol-active bool false)
(define-data-var total-registered-households uint u0)
(define-data-var total-compliant-households uint u0)
(define-data-var drought-start-date uint u0)
(define-data-var water-authority principal CONTRACT-OWNER)
(define-data-var restriction-counter uint u0)

;; Data Maps

;; Drought level history
(define-map drought-history
  { date: uint }
  {
    drought-level: uint,
    declared-by: principal,
    affected-households: uint,
    notes: (string-ascii 200),
    restrictions-count: uint
  }
)

;; Water restrictions by drought level
(define-map water-restrictions
  { restriction-id: uint }
  {
    drought-level: uint,
    restriction-type: (string-ascii 50),
    description: (string-ascii 200),
    penalty-amount: uint,
    is-active: bool,
    created-date: uint,
    created-by: principal
  }
)

;; Household compliance tracking
(define-map household-compliance
  { household-address: principal, date: uint }
  {
    drought-level: uint,
    is-compliant: bool,
    violation-type: (optional (string-ascii 100)),
    penalty-applied: bool,
    penalty-amount: uint,
    reported-by: principal,
    verified: bool
  }
)

;; Emergency water allocations
(define-map emergency-allocations
  { household-address: principal, allocation-period: uint }
  {
    allocated-gallons: uint,
    used-gallons: uint,
    remaining-gallons: uint,
    allocation-date: uint,
    expiry-date: uint,
    priority-level: uint,
    special-needs: bool
  }
)

;; Community response measures
(define-map community-measures
  { measure-id: uint }
  {
    measure-type: (string-ascii 50),
    description: (string-ascii 200),
    target-savings: uint,
    actual-savings: uint,
    start-date: uint,
    end-date: uint,
    is-active: bool,
    participating-households: uint
  }
)

;; Water conservation alerts
(define-map conservation-alerts
  { alert-id: uint }
  {
    alert-level: uint,
    message: (string-ascii 300),
    broadcast-date: uint,
    expiry-date: uint,
    target-audience: (string-ascii 50),
    is-active: bool,
    created-by: principal
  }
)

;; Authority permissions
(define-map authorized-officials
  { official: principal }
  {
    role: (string-ascii 30),
    permissions: uint,
    authorized-by: principal,
    authorization-date: uint,
    is-active: bool
  }
)

;; Private Functions

;; Check if caller is authorized
(define-private (is-authorized (caller principal))
  (or (is-eq caller CONTRACT-OWNER)
      (is-eq caller (var-get water-authority))
      (is-some (map-get? authorized-officials { official: caller }))
  )
)

;; Validate drought level
(define-private (is-valid-drought-level (level uint))
  (and (>= level DROUGHT-NORMAL) (<= level DROUGHT-EXCEPTIONAL))
)

;; Calculate penalty amount based on violation and drought level
(define-private (calculate-penalty (drought-level uint) (violation-severity uint))
  (let
    (
      (base-penalty (* drought-level u50))  ;; $50 per drought level
      (severity-multiplier (+ u1 violation-severity))
    )
    (* base-penalty severity-multiplier)
  )
)

;; Get current date (simplified)
(define-private (get-current-date)
  (/ stacks-block-height u144)  ;; Approximate days since genesis
)

;; Check if household has special needs
(define-private (has-special-needs (household principal))
  ;; Simplified check - would integrate with household registry
  false
)

;; Calculate emergency allocation based on household size and needs
(define-private (calculate-emergency-allocation (household-size uint) (special-needs bool))
  (let
    (
      (base-allocation (* household-size u150))  ;; 150 gallons per person
      (special-needs-bonus (if special-needs u500 u0))
    )
    (if (<= (+ base-allocation special-needs-bonus) MAX-EMERGENCY-ALLOCATION)
      (+ base-allocation special-needs-bonus)
      MAX-EMERGENCY-ALLOCATION
    )
  )
)

;; Public Functions

;; Declare drought level (only authorized officials)
(define-public (declare-drought-level 
    (new-level uint)
    (notes (string-ascii 200))
  )
  (let
    (
      (caller tx-sender)
      (current-date (get-current-date))
    )
    ;; Check authorization
    (asserts! (is-authorized caller) ERR-NOT-AUTHORIZED)
    
    ;; Validate drought level
    (asserts! (is-valid-drought-level new-level) ERR-INVALID-DROUGHT-LEVEL)
    
    ;; Record in history
    (map-set drought-history
      { date: current-date }
      {
        drought-level: new-level,
        declared-by: caller,
        affected-households: (var-get total-registered-households),
        notes: notes,
        restrictions-count: u0  ;; Will be updated as restrictions are added
      }
    )
    
    ;; Update current level
    (var-set current-drought-level new-level)
    
    ;; Set drought start date if moving from normal to higher level
    (if (and (is-eq (var-get current-drought-level) DROUGHT-NORMAL) (> new-level DROUGHT-NORMAL))
      (var-set drought-start-date current-date)
      true
    )
    
    ;; Activate emergency protocol if level is emergency or higher
    (var-set emergency-protocol-active (>= new-level DROUGHT-EMERGENCY))
    
    (ok new-level)
  )
)

;; Create water restriction
(define-public (create-restriction 
    (restriction-type (string-ascii 50))
    (description (string-ascii 200))
    (penalty-amount uint)
  )
  (let
    (
      (caller tx-sender)
      (new-id (+ (var-get restriction-counter) u1))
      (current-level (var-get current-drought-level))
    )
    ;; Check authorization
    (asserts! (is-authorized caller) ERR-NOT-AUTHORIZED)
    
    ;; Create restriction
    (map-set water-restrictions
      { restriction-id: new-id }
      {
        drought-level: current-level,
        restriction-type: restriction-type,
        description: description,
        penalty-amount: penalty-amount,
        is-active: true,
        created-date: (get-current-date),
        created-by: caller
      }
    )
    
    ;; Update counter
    (var-set restriction-counter new-id)
    
    (ok new-id)
  )
)

;; Report compliance violation
(define-public (report-violation 
    (household-address principal)
    (violation-type (string-ascii 100))
    (violation-severity uint)
  )
  (let
    (
      (caller tx-sender)
      (current-date (get-current-date))
      (current-level (var-get current-drought-level))
      (penalty (calculate-penalty current-level violation-severity))
    )
    ;; Check authorization
    (asserts! (is-authorized caller) ERR-NOT-AUTHORIZED)
    
    ;; Check if already reported for this date
    (asserts! (is-none (map-get? household-compliance 
                                { household-address: household-address, date: current-date }))
              ERR-ALREADY-REPORTED)
    
    ;; Record violation
    (map-set household-compliance
      { household-address: household-address, date: current-date }
      {
        drought-level: current-level,
        is-compliant: false,
        violation-type: (some violation-type),
        penalty-applied: true,
        penalty-amount: penalty,
        reported-by: caller,
        verified: false
      }
    )
    
    (ok penalty)
  )
)

;; Report compliance (good behavior)
(define-public (report-compliance (household-address principal))
  (let
    (
      (caller tx-sender)
      (current-date (get-current-date))
      (current-level (var-get current-drought-level))
    )
    ;; Check authorization
    (asserts! (is-authorized caller) ERR-NOT-AUTHORIZED)
    
    ;; Check if already reported for this date
    (asserts! (is-none (map-get? household-compliance 
                                { household-address: household-address, date: current-date }))
              ERR-ALREADY-REPORTED)
    
    ;; Record compliance
    (map-set household-compliance
      { household-address: household-address, date: current-date }
      {
        drought-level: current-level,
        is-compliant: true,
        violation-type: none,
        penalty-applied: false,
        penalty-amount: u0,
        reported-by: caller,
        verified: true
      }
    )
    
    ;; Update compliant households counter
    (var-set total-compliant-households (+ (var-get total-compliant-households) u1))
    
    (ok true)
  )
)

;; Allocate emergency water
(define-public (allocate-emergency-water 
    (household-address principal)
    (household-size uint)
    (allocation-period uint)
  )
  (let
    (
      (caller tx-sender)
      (is-emergency (var-get emergency-protocol-active))
      (special-needs (has-special-needs household-address))
      (allocation-amount (calculate-emergency-allocation household-size special-needs))
      (current-date (get-current-date))
    )
    ;; Check authorization and emergency status
    (asserts! (is-authorized caller) ERR-NOT-AUTHORIZED)
    (asserts! is-emergency ERR-EMERGENCY-NOT-ACTIVE)
    
    ;; Create allocation
    (map-set emergency-allocations
      { household-address: household-address, allocation-period: allocation-period }
      {
        allocated-gallons: allocation-amount,
        used-gallons: u0,
        remaining-gallons: allocation-amount,
        allocation-date: current-date,
        expiry-date: (+ current-date u30),  ;; 30 days validity
        priority-level: (if special-needs u2 u1),
        special-needs: special-needs
      }
    )
    
    (ok allocation-amount)
  )
)

;; Create conservation alert
(define-public (create-conservation-alert 
    (alert-level uint)
    (message (string-ascii 300))
    (target-audience (string-ascii 50))
    (validity-days uint)
  )
  (let
    (
      (caller tx-sender)
      (current-date (get-current-date))
      (alert-id (+ stacks-block-height (stx-get-balance tx-sender)))  ;; Simple ID generation
    )
    ;; Check authorization
    (asserts! (is-authorized caller) ERR-NOT-AUTHORIZED)
    
    ;; Create alert
    (map-set conservation-alerts
      { alert-id: alert-id }
      {
        alert-level: alert-level,
        message: message,
        broadcast-date: current-date,
        expiry-date: (+ current-date validity-days),
        target-audience: target-audience,
        is-active: true,
        created-by: caller
      }
    )
    
    (ok alert-id)
  )
)

;; Authorize official
(define-public (authorize-official 
    (official principal)
    (role (string-ascii 30))
    (permissions uint)
  )
  (begin
    ;; Only contract owner can authorize officials
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    (map-set authorized-officials
      { official: official }
      {
        role: role,
        permissions: permissions,
        authorized-by: tx-sender,
        authorization-date: (get-current-date),
        is-active: true
      }
    )
    
    (ok true)
  )
)

;; Update water authority
(define-public (set-water-authority (new-authority principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set water-authority new-authority)
    (ok true)
  )
)

;; Read-only Functions

;; Get current drought status
(define-read-only (get-drought-status)
  {
    current-level: (var-get current-drought-level),
    emergency-active: (var-get emergency-protocol-active),
    drought-start-date: (var-get drought-start-date),
    total-households: (var-get total-registered-households),
    compliant-households: (var-get total-compliant-households)
  }
)

;; Get drought history for date
(define-read-only (get-drought-history (date uint))
  (map-get? drought-history { date: date })
)

;; Get water restriction
(define-read-only (get-restriction (restriction-id uint))
  (map-get? water-restrictions { restriction-id: restriction-id })
)

;; Get household compliance for date
(define-read-only (get-household-compliance (household-address principal) (date uint))
  (map-get? household-compliance { household-address: household-address, date: date })
)

;; Get emergency allocation
(define-read-only (get-emergency-allocation (household-address principal) (allocation-period uint))
  (map-get? emergency-allocations { household-address: household-address, allocation-period: allocation-period })
)

;; Get conservation alert
(define-read-only (get-conservation-alert (alert-id uint))
  (map-get? conservation-alerts { alert-id: alert-id })
)

;; Check if official is authorized
(define-read-only (is-official-authorized (official principal))
  (match (map-get? authorized-officials { official: official })
    auth-data (get is-active auth-data)
    false
  )
)

;; Get contract statistics
(define-read-only (get-contract-stats)
  {
    current-drought-level: (var-get current-drought-level),
    emergency-protocol-active: (var-get emergency-protocol-active),
    total-registered-households: (var-get total-registered-households),
    total-compliant-households: (var-get total-compliant-households),
    drought-start-date: (var-get drought-start-date),
    water-authority: (var-get water-authority),
    restriction-counter: (var-get restriction-counter)
  }
)
