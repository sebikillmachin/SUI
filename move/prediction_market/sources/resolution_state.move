module prediction_market::resolution_state {
    use sui::balance;
    use sui::balance::Balance;

    /// Pending optimistic resolution. Challenge data kept inline to avoid drop constraints.
    public struct PendingResolution<phantom T> has store {
        proposer: address,
        proposed_yes: bool,
        bond: Balance<T>,
        has_challenge: bool,
        challenge_challenger: address,
        challenge_outcome_yes: bool,
        challenge_bond: Balance<T>,
    }

    /// Placeholder value when no pending resolution exists.
    public fun empty<T>(): PendingResolution<T> {
        PendingResolution<T> {
            proposer: @0x0,
            proposed_yes: false,
            bond: balance::zero<T>(),
            has_challenge: false,
            challenge_challenger: @0x0,
            challenge_outcome_yes: false,
            challenge_bond: balance::zero<T>(),
        }
    }

    /// Populate an empty pending slot.
    public fun start<T>(state: &mut PendingResolution<T>, proposer: address, proposed_yes: bool, bond: Balance<T>) {
        state.proposer = proposer;
        state.proposed_yes = proposed_yes;
        let cleared = balance::withdraw_all(&mut state.bond);
        balance::join(&mut state.bond, cleared);
        balance::join(&mut state.bond, bond);
        state.has_challenge = false;
        state.challenge_challenger = proposer;
        state.challenge_outcome_yes = proposed_yes;
        let cleared_challenge = balance::withdraw_all(&mut state.challenge_bond);
        balance::join(&mut state.bond, cleared_challenge);
    }

    public fun set_challenge<T>(state: &mut PendingResolution<T>, challenger: address, outcome_yes: bool, bond: Balance<T>) {
        balance::join(&mut state.challenge_bond, bond);
        state.has_challenge = true;
        state.challenge_challenger = challenger;
        state.challenge_outcome_yes = outcome_yes;
    }

    /// Consume the pending resolution, reset to blank, and return the merged bonds plus outcome.
    public fun consume<T>(state: &mut PendingResolution<T>): (bool, Balance<T>) {
        let outcome = state.proposed_yes;
        let mut merged = balance::withdraw_all(&mut state.bond);
        let challenge_bal = balance::withdraw_all(&mut state.challenge_bond);
        balance::join(&mut merged, challenge_bal);
        state.proposer = @0x0;
        state.proposed_yes = false;
        state.has_challenge = false;
        state.challenge_challenger = @0x0;
        state.challenge_outcome_yes = false;
        (outcome, merged)
    }
}
