# State
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/interfaces/IAutocallEngine.sol)


```solidity
enum State {
    Created,
    Priced,
    Active,
    ObservationPending,
    Autocalled,
    MaturityCheck,
    NoKISettle,
    KISettle,
    Settled,
    Rolled,
    EmergencyPaused,
    Cancelled
}
```

