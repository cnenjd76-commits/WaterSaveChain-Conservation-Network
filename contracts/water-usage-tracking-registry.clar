;; Water Usage Tracking Registry Contract
;; Monitor residential water usage patterns and identify conservation opportunities
;; Tracks household registration, daily usage recording, and historical data maintenance

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-HOUSEHOLD-EXISTS (err u402))
(define-constant ERR-HOUSEHOLD-NOT-FOUND (err u403))
(define-constant ERR-INVALID-USAGE (err u404))
(define-constant ERR-INVALID-DATE (err u405))
(define-constant ERR-FUTURE-DATE (err u406))
(define-constant ERR-DUPLICATE-READING (err u407))

;; Maximum daily usage threshold (in gallons)
(define-constant MAX-DAILY-USAGE u10000)

;; Data Variables
(define-data-var household-counter uint u0)
(define-data-var total-households uint u0)
(define-data-var total-daily-usage uint u0)
(define-data-var contract-administrator principal CONTRACT-OWNER)

;; Data Maps

;; Household registration data
(define-map households
  { household-id: uint }
  {
    owner: principal,
    address: (string-ascii 100),
    registration-date: uint,
    meter-id: (string-ascii 50),
    household-size: uint,
    is-active: bool,
    total-usage: uint,
    baseline-usage: uint
  }
)

;; Daily water usage readings
(define-map daily-usage
  { household-id: uint, date: uint }
  {
    usage-gallons: uint,
    reading-time: uint,
    meter-reader: principal,
    is-verified: bool,
    temperature: uint,
    notes: (optional (string-ascii 200))
  }
)

;; Household lookup by owner
(define-map household-by-owner
  { owner: principal }
  { household-id: uint }
)

;; Monthly usage summaries
(define-map monthly-summaries
  { household-id: uint, year: uint, month: uint }
  {
    total-usage: uint,
    avg-daily-usage: uint,
    peak-usage-day: uint,
    lowest-usage-day: uint,
    conservation-score: uint,
    days-recorded: uint
  }
)

;; Conservation achievements
(define-map conservation-achievements
  { household-id: uint }
  {
    total-savings: uint,
    streak-days: uint,
    best-streak: uint,
    achievements-earned: uint,
    last-achievement-date: uint
  }
)

;; Private Functions

;; Check if caller is authorized (owner or administrator)
(define-private (is-authorized (caller principal))
  (or (is-eq caller CONTRACT-OWNER)
      (is-eq caller (var-get contract-administrator))
  )
)

;; Validate household exists
(define-private (household-exists (household-id uint))
  (is-some (map-get? households { household-id: household-id }))
)

;; Calculate conservation score based on usage vs baseline
(define-private (calculate-conservation-score (current-usage uint) (baseline-usage uint))
  (if (is-eq baseline-usage u0)
    u50  ;; Default score if no baseline
    (if (<= current-usage baseline-usage)
      (+ u50 (/ (* (- baseline-usage current-usage) u50) baseline-usage))
      (if (<= u50 (/ (* (- current-usage baseline-usage) u50) baseline-usage))
        u0
        (- u50 (/ (* (- current-usage baseline-usage) u50) baseline-usage))
      )
    )
  )
)

;; Get current date (simplified - using block height as proxy)
(define-private (get-current-date)
  (/ stacks-block-height u144)  ;; Approximate days since genesis
)

;; Validate date is not in future
(define-private (is-valid-date (date uint))
  (<= date (get-current-date))
)

;; Check for duplicate readings on same date
(define-private (has-reading-for-date (household-id uint) (date uint))
  (is-some (map-get? daily-usage { household-id: household-id, date: date }))
)

;; Public Functions

;; Register a new household
(define-public (register-household 
    (address (string-ascii 100))
    (meter-id (string-ascii 50))
    (household-size uint)
  )
  (let
    (
      (new-id (+ (var-get household-counter) u1))
      (caller tx-sender)
    )
    ;; Check if household already exists for this owner
    (asserts! (is-none (map-get? household-by-owner { owner: caller }))
              ERR-HOUSEHOLD-EXISTS)
    
    ;; Register the household
    (map-set households
      { household-id: new-id }
      {
        owner: caller,
        address: address,
        registration-date: (get-current-date),
        meter-id: meter-id,
        household-size: household-size,
        is-active: true,
        total-usage: u0,
        baseline-usage: u0
      }
    )
    
    ;; Set owner lookup
    (map-set household-by-owner
      { owner: caller }
      { household-id: new-id }
    )
    
    ;; Initialize conservation tracking
    (map-set conservation-achievements
      { household-id: new-id }
      {
        total-savings: u0,
        streak-days: u0,
        best-streak: u0,
        achievements-earned: u0,
        last-achievement-date: u0
      }
    )
    
    ;; Update counters
    (var-set household-counter new-id)
    (var-set total-households (+ (var-get total-households) u1))
    
    (ok new-id)
  )
)

;; Record daily water usage
(define-public (record-daily-usage 
    (household-id uint)
    (date uint)
    (usage-gallons uint)
    (temperature uint)
    (notes (optional (string-ascii 200)))
  )
  (let
    (
      (caller tx-sender)
      (household-data (unwrap! (map-get? households { household-id: household-id })
                                ERR-HOUSEHOLD-NOT-FOUND))
    )
    ;; Validate caller is household owner or authorized
    (asserts! (or (is-eq caller (get owner household-data))
                  (is-authorized caller))
              ERR-NOT-AUTHORIZED)
    
    ;; Validate usage amount
    (asserts! (and (> usage-gallons u0) (<= usage-gallons MAX-DAILY-USAGE))
              ERR-INVALID-USAGE)
    
    ;; Validate date
    (asserts! (is-valid-date date) ERR-FUTURE-DATE)
    
    ;; Check for duplicate reading
    (asserts! (not (has-reading-for-date household-id date))
              ERR-DUPLICATE-READING)
    
    ;; Record the usage
    (map-set daily-usage
      { household-id: household-id, date: date }
      {
        usage-gallons: usage-gallons,
        reading-time: stacks-block-height,
        meter-reader: caller,
        is-verified: (is-authorized caller),
        temperature: temperature,
        notes: notes
      }
    )
    
    ;; Update household total usage
    (map-set households
      { household-id: household-id }
      (merge household-data { total-usage: (+ (get total-usage household-data) usage-gallons) })
    )
    
    ;; Update global counter
    (var-set total-daily-usage (+ (var-get total-daily-usage) usage-gallons))
    
    (ok true)
  )
)

;; Set household baseline usage for conservation tracking
(define-public (set-baseline-usage (household-id uint) (baseline-usage uint))
  (let
    (
      (caller tx-sender)
      (household-data (unwrap! (map-get? households { household-id: household-id })
                                ERR-HOUSEHOLD-NOT-FOUND))
    )
    ;; Only household owner or admin can set baseline
    (asserts! (or (is-eq caller (get owner household-data))
                  (is-authorized caller))
              ERR-NOT-AUTHORIZED)
    
    ;; Update baseline
    (map-set households
      { household-id: household-id }
      (merge household-data { baseline-usage: baseline-usage })
    )
    
    (ok true)
  )
)

;; Generate monthly summary
(define-public (generate-monthly-summary 
    (household-id uint)
    (year uint)
    (month uint)
  )
  (let
    (
      (caller tx-sender)
      (household-data (unwrap! (map-get? households { household-id: household-id })
                                ERR-HOUSEHOLD-NOT-FOUND))
    )
    ;; Only household owner or admin can generate summary
    (asserts! (or (is-eq caller (get owner household-data))
                  (is-authorized caller))
              ERR-NOT-AUTHORIZED)
    
    ;; Create monthly summary (simplified calculation)
    (map-set monthly-summaries
      { household-id: household-id, year: year, month: month }
      {
        total-usage: u0,        ;; Would calculate from daily readings
        avg-daily-usage: u0,    ;; Would calculate average
        peak-usage-day: u0,     ;; Would find highest day
        lowest-usage-day: u0,   ;; Would find lowest day
        conservation-score: (calculate-conservation-score u0 (get baseline-usage household-data)),
        days-recorded: u0       ;; Would count actual readings
      }
    )
    
    (ok true)
  )
)

;; Update contract administrator
(define-public (set-administrator (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-administrator new-admin)
    (ok true)
  )
)

;; Read-only functions

;; Get household information
(define-read-only (get-household (household-id uint))
  (map-get? households { household-id: household-id })
)

;; Get household by owner
(define-read-only (get-household-by-owner (owner principal))
  (match (map-get? household-by-owner { owner: owner })
    lookup (map-get? households { household-id: (get household-id lookup) })
    none
  )
)

;; Get daily usage for specific date
(define-read-only (get-daily-usage (household-id uint) (date uint))
  (map-get? daily-usage { household-id: household-id, date: date })
)

;; Get monthly summary
(define-read-only (get-monthly-summary (household-id uint) (year uint) (month uint))
  (map-get? monthly-summaries { household-id: household-id, year: year, month: month })
)

;; Get conservation achievements
(define-read-only (get-conservation-achievements (household-id uint))
  (map-get? conservation-achievements { household-id: household-id })
)

;; Get contract statistics
(define-read-only (get-contract-stats)
  {
    total-households: (var-get total-households),
    household-counter: (var-get household-counter),
    total-daily-usage: (var-get total-daily-usage),
    administrator: (var-get contract-administrator)
  }
)
