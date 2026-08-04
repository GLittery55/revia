# Reflection Card Adaptation Specification

## Design intent

Reflection Cards are projective prompts adapted from the visual and relational tensions of the Major Arcana. They are not tarot readings. The system removes card names, numbers, divinatory claims, upright/reversed meanings, moral judgments, and predictions. A card should be ambiguous enough to support several interpretations and concrete enough to help a user notice something they had not yet articulated.

## Adaptation procedure

1. Identify the source image's broad visual tension, not its canonical tarot meaning.
2. Remove named characters, symbols, captions, numbers, and other cues that reveal a conventional category when feasible.
3. Express the remaining affordance as a non-directional pair, such as "pausing and moving forward" or "holding on and letting go."
4. Reject any phrase that implies fate, personality diagnosis, blame, virtue, danger, or a correct interpretation.
5. Check that at least three materially different readings remain plausible.
6. Have independent reviewers describe the image before seeing the weak prompt. Revise when the prompt dominates their interpretation.
7. Record the source, transformation decisions, weak prompt, reviewer interpretations, and revision history.

## Interaction order

1. The user discloses a situation for three to five assistant turns, stopping once a bounded event, felt experience, self-meaning or judgment, and at least one constraint, conflict, or coping response are clear.
2. Tender grounding acknowledges the pain and separates the concrete situation from a global identity judgment. The user confirms or corrects this account.
3. At most one already-authorized tracking cue may be presented automatically as uncertain background. The user, not the record or model, decides whether it fits.
4. The assistant gives a short, correctable context summary before any card is selected.
5. In the card-mediated condition, the application draws one card locally by uniform chance, independently of route, emotion, tracking, and model output.
6. The card is shown without source identity or weak prompt. The assistant waits for a successful image-display event before asking about it; a failed load retries the same card.
7. The user describes what is happening. The assistant may ask at most one additional image-only question using the user's words.
8. A separate invitation asks whether the user's own image narrative connects to real life. A connection may be absent; after at most one scaffold and a second failed connection, the card is left unconnected.
9. With a user-authored connection, the assistant asks first about circumstances or limits that deserve acknowledgment and then, in a later turn, about agency, boundaries, repair, or change the user still sees as available.
10. An integrated narrative is confirmed before an optional action. A final narrative is confirmed before completion.

## Narrative integration

The post-card interpretation should form one coherent account across four evidence layers:

- Self-disclosure: what happened, what the user felt, and what matters to them.
- Self-tracking: uncertain context about recent capacity or load, with missingness and alternative explanations.
- User card interpretation: the user's own noticed image, tension, association, or metaphor.
- Weak card affordance: an optional secondary tension that cannot determine the conclusion.

The resulting attribution distinguishes:

- circumstances and constraints;
- possible influences on available capacity;
- uncertainty and information the system does not have;
- agency, boundary, need, and proportionate responsibility;
- the current self-compassion balance: tender, fierce, or integrated.

The system must reduce global self-condemnation without erasing responsibility. It must not infer a psychological trait, diagnose stress from HRV, or treat a card as evidence.

## Practice generation

The dialogue may include at most one optional self-compassion practice. Its direction and wording begin
with the user and are explicitly confirmed. It must:

- follow directly from the integrated narrative;
- be categorized as care, repair, protection, or change;
- include a concrete cue, duration, or boundary;
- be feasible within the user's stated capacity;
- balance tender acceptance with fierce action when needed;
- avoid confrontation instructions and predicted outcomes;
- preserve "not ready" as a valid choice.

Declining an action is a complete result. The model must not turn an unconnected card into a generic
practice or use action generation to compensate for missing reflection.

## Validation criteria

- Interpretation ownership: a reviewer can identify which claims came from the user rather than the card or model.
- Ambiguity: no single conventional meaning is required to understand the card.
- Context fidelity: every attribution is traceable to disclosed or tracking evidence.
- Epistemic humility: uncertain clues include alternatives and never become causal claims.
- Compassion completeness: the response checks kindness/judgment, humanity/isolation, mindfulness/overidentification, and tender/fierce balance.
- Action coherence: the single practice is a logical consequence of the narrative rather than a generic wellness suggestion.
