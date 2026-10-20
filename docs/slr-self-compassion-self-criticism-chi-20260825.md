# Systematic Literature Review: Self-Compassion in the Context of Self-Criticism

**Date**: 2026-08-25  
**Papers surveyed**: 42  
**Scope**: Self-compassion in episodes of self-criticism, failure, shame, and perceived inadequacy, with attention to implications for CHI research on interactive reflection  
**Citation format**: BibTeX  

## Executive Summary

Across conceptual reviews, correlational studies, interventions, and emerging interactive systems, self-compassion is consistently framed as a way of responding to pain or failure with kindness, common humanity, and balanced awareness rather than global self-condemnation \cite{neff2003alternative,neff2023theory,barnard2011conceptualizations}. The evidence base associates self-criticism with depression, shame, disordered eating, and other forms of distress, while meta-analyses suggest that compassion-oriented interventions can reduce self-criticism and improve psychosocial outcomes \cite{ehret2014examining,wakelin2021effectiveness,ferrari2019interventions,paranjothy2024meta}. Crucially for Beyond Comfort, experimental and measurement work indicates that self-compassion need not mean complacency: it can coexist with self-improvement motivation and action directed at alleviating suffering \cite{breines2012motivation,gilbert2017engagement}. For CHI, the major open question is therefore not whether technology should simply make users feel better, but how an interactive system can support a compassionate yet candid account without authoring consequential interpretations on the user's behalf.

## Methodology

The requested `systematic-literature-review` workflow first searched arXiv once on 2026-08-25 with the relevance-ranked query `self compassion`, returning four papers. Because arXiv coverage was insufficient for the requested minimum of 30 papers and the topic is grounded primarily in psychology and health journals, a supplementary T1-style multi-source workflow queried OpenAlex, which indexes CrossRef, PubMed, and arXiv-deposited works, using `self-compassion self-criticism`. The 35 highest-relevance journal or book records were retained after DOI/title deduplication. Three foundational works were then added through exact-title searches: the original self-compassion conceptualization, the self-improvement motivation experiments, and the Annual Review synthesis. The final set contains 38 journal articles or chapters and four arXiv preprints.

Metadata and abstract-level evidence were extracted in nine batches by parallel language-model agents. Missing abstracts were explicitly retained as metadata-only records rather than supplemented with invented methods or findings. Cross-paper synthesis was conducted for a CHI audience: clinical studies establish the construct's boundary conditions, whereas the proposed interaction-design gap concerns how reflective technologies distribute interpretive authority.

**Limitations of this review**: This is a structured rapid review rather than a preregistered systematic review. It does not include full-text risk-of-bias assessment, forward/backward citation chasing, or unpublished null findings. OpenAlex relevance ranking can overrepresent papers containing both query phrases. Four included arXiv papers are not necessarily peer reviewed, and several journal records lacked abstracts; claims in the CHI-ready subsection therefore rely primarily on conceptual reviews, meta-analyses, experiments, and records with adequate methodological detail.

## Themes

### Theme 1: Self-compassion is a relational stance toward failure, not simply positive self-evaluation

The foundational account defines self-compassion through self-kindness, common humanity, and mindfulness, contrasted with self-judgment, isolation, and overidentification \cite{neff2003alternative,neff2023theory}. Reviews position these components as a way of relating to oneself specifically during pain, failure, or inadequacy, rather than as generalized positive self-esteem \cite{barnard2011conceptualizations,neff2008selfcompassion}. This distinction matters for HCI: a reflective system should not treat self-compassion as praise, mood repair alone, or indiscriminate reassurance.

Measurement research complicates any simple use of a single score. López et al. question combining positive and negative Self-Compassion Scale components into one total, while Neff defends its theoretical coherence \cite{lopez2015reconsideration,neff2015scale}. Other work develops negative-component measures of self-criticism, scenario-based state measures, and scales that distinguish compassionate engagement from compassionate action \cite{monteromarin2016selfcriticism,falconer2015mood,gilbert2017engagement}. For Beyond Comfort, this supports treating self-compassion as an integrated design target while separately observing self-judgment, contextual awareness, and action-related distinctions.

### Theme 2: Self-criticism is linked to distress across settings, but much of the evidence is correlational

Studies connect self-criticism and low self-compassion to depression, shame, eating-disorder symptoms, trauma-related distress, social anxiety, postpartum depression, and reduced quality of life \cite{ehret2014examining,joeng2015mediators,zhang2017selfcriticism,kaurin2018buffers,pedro2019postpartum,paranjothy2024meta}. Similar relationships appear in athletes, helping professions, therapeutic students, people with cystic fibrosis, and people recovering from psychosis \cite{killham2018women,ondrejkova2022prevalence,kotera2019therapeutic,kauser2021associations,waite2015recovery}. These convergent settings justify examining everyday self-critical episodes, but most studies do not establish that increasing self-compassion alone causes durable behavioral or clinical change.

The literature also indicates that self-criticism is not only a high score on the inverse of self-kindness. It may involve threat, shame, comparison, global identity judgments, and difficulty accessing reassurance \cite{gilbert2009introducing,longe2009neural}. A CHI system should therefore distinguish a concrete appraisal of behavior from whole-person condemnation rather than attempting to remove every negative evaluation.

### Theme 3: Compassion can be difficult, frightening, or resisted

Highly self-critical people may fear compassion for themselves, struggle to receive compassion from others, or experience warmth and reassurance as unsafe \cite{gilbert2010fears,gilbert2011fears,joeng2015mediators,naismith2019abuse}. Cross-cultural and clinical work suggests that receptivity to compassion can shape how self-criticism relates to depressive outcomes \cite{hermanto2016ability}. This challenges a common technology-design assumption that supportive wording is intrinsically experienced as supportive.

For interaction design, compassion should therefore be offered as a negotiable stance rather than imposed as a mandatory positive reframe. A user's rejection, uncertainty, or inability to connect is meaningful interactional evidence, not a failure that justifies escalating reassurance.

### Theme 4: Self-compassion can support action rather than erase responsibility

The strongest direct evidence against the complacency objection comes from four experiments showing that self-compassion after mistakes can increase incremental beliefs and self-improvement motivation across personal weaknesses, moral transgressions, and test performance \cite{breines2012motivation}. The compassionate engagement-and-action model likewise defines compassion as both noticing suffering and acting, when possible, to alleviate it \cite{gilbert2017engagement}. Self-compassion is therefore compatible with examining behavior, impact, boundaries, repair, and change.

This does not establish a universal causal pathway from compassion to responsible action. Intervention effects vary, and some participants fear or resist compassion. For Beyond Comfort, the defensible claim is narrower: a well-designed reflection should not force a choice between acknowledging suffering and preserving agency. The system can support both while leaving the specific interpretation and action optional.

### Theme 5: Interventions reduce self-criticism, but interactive mechanisms remain under-specified

Compassionate mind training, compassion-focused therapy, online interventions, and meta-analyses provide evidence that self-compassion can be cultivated and that interventions can reduce self-criticism \cite{gilbert2006compassionate,gilbert2009introducing,krieger2018internet,wakelin2021effectiveness,ferrari2019interventions}. Technology-mediated implementations include embodied virtual reality, mixed-reality teacher training, LLM-augmented behavior-change coaching, and AI-supported reflection on wellbeing data \cite{falconer2014embodying,chehayeb2025coregulation,jorke2025bloom,zhu2026kriya}.

However, most studies operationalize self-compassion as an outcome, exercise, script, or therapeutic orientation. They provide less evidence about how moment-to-moment interactive systems should distribute the work of interpreting why an event happened, what it says about the self, and what responsibility remains. This is the key bridge from the present subsection to `Technology-Mediated Reflection`.

## Convergences and Disagreements

**Convergences**:

- Conceptual and review papers agree that self-compassion concerns how people relate to pain or failure, not generic positive evaluation \cite{neff2003alternative,barnard2011conceptualizations,neff2023theory}.
- Studies across populations repeatedly associate self-criticism with distress and self-compassion or receptivity to compassion with resilience-related outcomes \cite{ehret2014examining,joeng2015mediators,kaurin2018buffers,hermanto2016ability}.
- Intervention reviews converge on the conclusion that compassion-oriented interventions can reduce self-criticism, though effect size, population, and intervention format vary \cite{wakelin2021effectiveness,ferrari2019interventions}.
- Experimental evidence contradicts the simple assumption that self-compassion necessarily reduces motivation to improve \cite{breines2012motivation}.

**Disagreements and unresolved tensions**:

- Researchers disagree over whether positive and negative Self-Compassion Scale components form a defensible total score or should be treated separately \cite{lopez2015reconsideration,neff2015scale,monteromarin2016selfcriticism}.
- The literature alternates between self-compassion as a trait, a state response to a scenario, a set of competencies, and an intervention target \cite{falconer2015mood,gilbert2017engagement,neff2023theory}.
- Cross-sectional buffering and mediation models are often discussed in mechanistic language even though temporal and causal ordering is not established.
- Therapeutic models emphasize soothing and safeness, while action-oriented models emphasize engagement and alleviation; these are better treated as complementary functions than as mutually exclusive routes.

## Gaps and Open Questions for CHI

1. **Interpretation authorship**: The literature says relatively little about who first formulates a consequential interpretation in an interactive reflection: the user, the system, or a shared artifact.
2. **Moment-level process evidence**: Self-compassion is usually measured before and after an intervention. Few studies trace how a specific self-critical statement becomes a more contextualized account turn by turn.
3. **Compassion without epistemic overreach**: Supportive systems can acknowledge suffering, but evidence is limited on how they can examine behavior and impact without asserting motives, blame, or causal explanations.
4. **Context as a contestable cue**: Emerging AI systems use personal data for reflection, but little work tests designs in which data relevance must be explicitly accepted, qualified, or rejected before it shapes later interpretation \cite{zhu2026kriya}.
5. **Beyond scripted exercises**: Existing digital interventions often deliver predefined compassion exercises. The design space for user-authored, ambiguous, and negotiable reflective materials remains underexplored.
6. **Cultural and population validity**: Much evidence comes from Western student or clinical samples, and cultural differences in self-construal, compassion, and responsibility remain incompletely understood \cite{yamaguchi2014effects,hermanto2016ability}.

## CHI-Ready Related Work Subsection

The following draft is intentionally selective. It cites 14 works from the 42-paper evidence pool rather than compressing the whole review into the paper body.

```latex
\subsection{Self-Compassion in the Context of Self-Criticism}

Self-criticism often arises when people evaluate perceived failures,
mistakes, or unmet expectations. Although evaluating a specific behavior
can support learning, self-criticism can also expand into global judgments
of the self and become entangled with shame and depressive symptoms
~\cite{gilbert2009introducing,ehret2014examining,joeng2015mediators}.
Self-compassion offers a different way of relating to such experiences. It
is commonly conceptualized through self-kindness rather than harsh
self-judgment, common humanity rather than isolation, and mindful awareness
rather than overidentification with painful thoughts and feelings
~\cite{neff2003alternative,neff2023theory}. In this sense,
self-compassion does not deny that a difficult event occurred; it changes
how that event is held in relation to the broader self.

However, self-compassion is sometimes reduced to soothing distress or
reassuring oneself. This view overlooks its action-oriented function.
Contemporary accounts describe compassion as both engaging with suffering
and responding to it, which can involve care, protection, or change
~\cite{gilbert2017engagement,neff2023theory}. Compassion is also not
uniformly experienced as comforting. People high in self-criticism may find
it unfamiliar, difficult to receive, or even threatening
~\cite{gilbert2010fears,gilbert2011fears}. A compassionate response therefore
cannot be reduced to a reassuring script. It must remain open to how a person
understands the situation and what they see as requiring acknowledgment or
action.

Intervention studies support this broader account. Compassion-oriented
practices can reduce self-criticism and improve psychosocial outcomes,
although effects vary across populations and formats
~\cite{wakelin2021effectiveness,ferrari2019interventions}. Self-compassion
need not undermine accountability. Four experiments found
that responding compassionately after failure could increase motivation to
improve personal weaknesses, address moral transgressions, and perform better
on subsequent tasks~\cite{breines2012motivation}. Acknowledging pain and
contextual constraints can therefore coexist with examining specific
behavior, impact, boundaries, repair, and change. We use
\textit{self-compassionate candor} to describe this design goal, rather than
as a distinct psychological construct: supporting a compassionate account
without treating compassion as automatic absolution.

Prior work has begun to operationalize self-compassion through online
compassion-focused interventions, embodied perspective-taking in virtual
reality, and LLM-supported behavior-change systems
~\cite{krieger2018internet,falconer2014embodying,jorke2025bloom}. These
systems operationalize self-compassion through structured exercises,
emotion regulation, or alternative perspective-taking. They provide less guidance on how
an interactive system might support compassionate acknowledgment together
with candid examination during a concrete self-critical episode. This gap
motivates compassionate candor as a design goal: helping users acknowledge
difficulty without global self-attack while retaining space to examine what
may require protection, responsibility, repair, or change. We next review
how technology has mediated reflective sensemaking.
```

## Evidence-to-Writing Map

| Claim needed in the CHI subsection | Strongest evidence type | Recommended citations | Boundary to preserve |
|---|---|---|---|
| Definition of self-compassion | Foundational concept + recent review | \cite{neff2003alternative,neff2023theory} | Do not equate it with praise or positive mood |
| Self-criticism can become globally harmful | Theory + cross-population associations | \cite{gilbert2009introducing,ehret2014examining,joeng2015mediators} | Associations do not establish causality |
| Self-compassion is not simply the inverse of self-criticism | Measurement debate | \cite{lopez2015reconsideration,neff2015scale,monteromarin2016selfcriticism} | Do not present a settled factor structure |
| Context-specific responding matters | Scenario-based measurement | \cite{falconer2015mood} | State response is not interchangeable with trait score |
| Interventions can reduce self-criticism | Systematic reviews/meta-analyses | \cite{wakelin2021effectiveness,ferrari2019interventions} | Avoid universal effectiveness claims |
| Compassion need not undermine change | Four experiments + action model | \cite{breines2012motivation,gilbert2017engagement} | Do not claim guaranteed responsibility or behavior change |
| Compassion may be resisted | Scale development + relational studies | \cite{gilbert2010fears,gilbert2011fears,hermanto2016ability} | Supportive language is not automatically experienced as supportive |
| CHI design gap | Synthesis across psychology and HCI | \cite{falconer2014embodying,jorke2025bloom,zhu2026kriya} | Present as an inference from the corpus, not a tested finding |

## Per-Paper Annotations

### \cite{lopez2015reconsideration} — “A Reconsideration of the Self-Compassion Scale's Total Score” (2015)

- **Research question**: Whether the Self-Compassion Scale supports a total score combining positive and negative components.
- **Methodology**: Factor-structure, reliability, and validity analysis in a representative community sample (1,643 analyzed).
- **Contribution**: Establishes a central measurement dispute relevant to avoiding an oversimplified “more compassion/less criticism” continuum.
- **Limitation**: Abstract-level metadata does not provide the full statistical model or all estimates.

### \cite{killham2018women} — “Women Athletes' Self-Compassion, Self-Criticism, and Perceived Sport Performance” (2018)

- **Research question**: How self-compassion and self-criticism relate to perceived athletic performance.
- **Methodology/findings**: Not determinable from the available metadata.
- **Limitation**: Included as evidence of domain breadth, not as a source for a directional claim.

### \cite{gilbert2011fears} — “Fears of Compassion and Happiness…” (2011)

- **Research question**: How fears of affiliative emotion relate to alexithymia, mindfulness, and self-criticism.
- **Contribution**: Supports the boundary condition that people high in self-criticism may resist apparently supportive framing.
- **Limitation**: The available abstract does not report effect sizes or complete methods.

### \cite{ehret2014examining} — “Examining Risk and Resilience Factors for Depression” (2014)

- **Research question**: Whether self-criticism and habitual self-compassion distinguish currently depressed, remitted, and never-depressed groups.
- **Methodology**: Between-group comparison across depression status.
- **Contribution**: Frequently cited risk/resilience framing.
- **Limitation**: Group differences do not alone establish prospective protection.

### \cite{kelly2016within} — “Within-Persons Predictors of Change During Eating Disorders Treatment” (2016)

- **Research question**: How within-person changes in compassion, criticism, shame, and symptoms influence one another during treatment.
- **Contribution**: Moves beyond static between-person associations toward process-level change.
- **Limitation**: Full temporal model and estimates were unavailable in the retrieved abstract.

### \cite{luoma2015shame} — “Shame, Self-Criticism, Self-Stigma, and Compassion in ACT” (2015)

- **Type**: Conceptual/review paper linking compassion with ACT approaches to shame and self-stigma.
- **Limitation**: Abstract unavailable; do not use for precise empirical claims without full-text verification.

### \cite{gilbert2008adolescence} — “Shame, Self-Criticism, and Self-Compassion in Adolescence” (2008)

- **Type**: Book chapter addressing developmental context.
- **Limitation**: Abstract and empirical details unavailable; use as conceptual background only.

### \cite{joeng2015mediators} — “Mediators Between Self-Criticism and Depression” (2015)

- **Methodology**: Online survey of 206 university students testing compassion-related mediators.
- **Contribution**: Shows that fear of compassion and perceived relational importance belong in the self-criticism pathway.
- **Limitation**: Cross-sectional mediation cannot establish temporal causality.

### \cite{gilbert2010fears} — “Fears of Compassion: Development of Three Self-Report Measures” (2010)

- **Methodology**: Development of scales for compassion toward others, from others, and toward self.
- **Contribution**: Operationalizes resistance to compassion instead of assuming it is universally welcomed.
- **Limitation**: The retrieved abstract omits full psychometric estimates.

### \cite{wakelin2021effectiveness} — “Effectiveness of Self-Compassion-Related Interventions…” (2021)

- **Methodology**: Systematic review and meta-analysis of 20 randomized controlled trials.
- **Contribution**: Direct synthesis of whether compassion-oriented interventions reduce self-criticism.
- **Limitation**: The retrieved abstract did not expose pooled estimates, heterogeneity, or moderator results.

### \cite{gilbert2009introducing} — “Introducing Compassion-Focused Therapy” (2009)

- **Type**: Theoretical and clinical introduction.
- **Contribution**: Frames shame and self-criticism as transdiagnostic and links compassion to safeness and affect regulation.
- **Limitation**: Not itself a comparative intervention trial.

### \cite{ondrejkova2022prevalence} — “Prevalence of Compassion Fatigue…” (2022)

- **Research question**: Prevalence and occupational variation in compassion fatigue and its relationships with compassion and criticism.
- **Limitation**: Detailed design and numerical results were absent from the retrieved abstract.

### \cite{neff2015scale} — “The Self-Compassion Scale Is a Valid and Theoretically Coherent Measure” (2015)

- **Type**: Measurement defense and theoretical response.
- **Contribution**: Represents the counter-position to critiques of the total score.
- **Limitation**: Abstract unavailable; cite alongside measurement critiques rather than as settled resolution.

### \cite{falconer2014embodying} — “Embodying Compassion” (2014)

- **Methodology**: Immersive VR embodiment with highly self-critical healthy women.
- **Contribution**: Demonstrates that interactive perspective-taking can operationalize compassion beyond text scripts.
- **Limitation**: Restricted sample and unclear durability/generalizability from abstract-level evidence.

### \cite{gilbert2006compassionate} — “Compassionate Mind Training…” (2006)

- **Methodology**: Theoretical overview plus uncontrolled group pilot.
- **Contribution**: Early intervention account for people high in shame and self-criticism who struggle with self-warmth.
- **Limitation**: Uncontrolled pilot cannot establish causal effectiveness.

### \cite{barnard2011conceptualizations} — “Self-Compassion: Conceptualizations, Correlates, & Interventions” (2011)

- **Type**: Broad review of definition, correlates, and interventions.
- **Contribution**: Useful bridge from psychological theory to applied research.
- **Limitation**: Search and appraisal procedures are not specified in the abstract.

### \cite{xavier2016nonsuicidal} — “Non-Suicidal Self-Injury in Adolescence…” (2016)

- **Research focus**: Shame, self-criticism, and fear of self-compassion in adolescent self-injury.
- **Limitation**: Abstract unavailable; retain only as population-specific evidence.

### \cite{falconer2015mood} — “Demonstrating Mood Repair with a Situation-Based Measure…” (2015)

- **Methodology**: Scenario-based scale development, online survey, and experiment.
- **Contribution**: Shows the value of measuring compassion/criticism as responses to specific situations rather than traits alone.
- **Limitation**: Retrieved abstract did not provide complete psychometric estimates.

### \cite{yamaguchi2014effects} — “Effects of Self-Construals, Self-Criticism, and Self-Compassion…” (2014)

- **Research focus**: Cultural/self-construal context around depressive symptoms.
- **Limitation**: Methods and results unavailable in retrieved metadata; do not make directional cultural claims from this record alone.

### \cite{zhang2017selfcriticism} — “Self-Criticism and Depressive Symptoms…” (2017)

- **Methodology**: Cross-sectional sample of 147 urban, low-income African Americans with a recent suicide attempt.
- **Contribution**: Tests self-compassion as a mediator in a high-risk, underserved population.
- **Limitation**: Cross-sectional design and specialized sample constrain causal and general conclusions.

### \cite{ferrari2019interventions} — “Self-Compassion Interventions and Psychosocial Outcomes” (2019)

- **Methodology**: Meta-analysis of randomized controlled trials.
- **Contribution**: Synthesizes intervention outcomes beyond self-criticism alone.
- **Limitation**: The available record lacks pooled estimates and risk-of-bias detail.

### \cite{gilbert2017engagement} — “Development of Compassionate Engagement and Action Scales” (2017)

- **Methodology**: Measure development from an evolutionary/motivational model.
- **Contribution**: Distinguishes engagement with suffering from action to alleviate it, directly supporting a comfort-and-action framing.
- **Limitation**: Complete psychometric evidence was not available in the abstract.

### \cite{naismith2019abuse} — “Abuse, Invalidation, and Lack of Early Warmth…” (2019)

- **Methodology**: Cross-sectional study of 53 people with personality disorder.
- **Contribution**: Shows that histories of warmth/invalidation may shape compassion and fear of compassion differently.
- **Limitation**: Small clinical sample and cross-sectional design.

### \cite{beaumont2016training} — “Does CFT Training…Increase Self-Compassion?” (2016)

- **Research question**: Whether professional training changes self-compassion, self-persecution, and self-criticism.
- **Limitation**: Detailed methods and results were not available in the retrieved record.

### \cite{neff2008selfcompassion} — “Self-Compassion Versus Global Self-Esteem” (2008)

- **Methodology**: Multi-study comparison; one reported study included 2,187 participants.
- **Contribution**: Positions self-compassion as less contingent and more stable than global self-esteem.
- **Limitation**: Full results and study structure require full-text confirmation.

### \cite{krieger2018internet} — “An Internet-Based Compassion-Focused Intervention…” (2018)

- **Methodology**: Randomized controlled trial for elevated self-criticism.
- **Contribution**: Establishes feasibility of technology-delivered compassion-focused intervention.
- **Limitation**: Abstract unavailable in retrieved metadata; do not state effect magnitude without verification.

### \cite{monteromarin2016selfcriticism} — “Self-Criticism: A Measure of Uncompassionate Behaviors…” (2016)

- **Methodology**: Factor/psychometric evaluation of negative Self-Compassion Scale components.
- **Contribution**: Provides a separable self-criticism operationalization.
- **Limitation**: Supports measurement debate rather than resolving it.

### \cite{kaurin2018buffers} — “Self-Compassion Buffers the Link…” (2018)

- **Methodology**: Self-report study of 123 trauma-exposed firefighters using moderation analysis.
- **Contribution**: Tests resilience under cumulative occupational trauma exposure.
- **Limitation**: Observational moderation does not establish causal buffering.

### \cite{kotera2019therapeutic} — “Mental Health of Therapeutic Students…” (2019)

- **Methodology**: Cross-sectional study of 145 counselling and occupational-therapy students.
- **Contribution**: Extends compassion/criticism relationships to future helping professionals.
- **Limitation**: Cross-sectional, self-report design.

### \cite{hermanto2016ability} — “Ability to Receive Compassion from Others…” (2016)

- **Methodology**: Cross-cultural multi-study moderation analysis.
- **Contribution**: Adds relational receptivity as a potential buffer rather than focusing on self-generated compassion alone.
- **Limitation**: Detailed cultural settings and effect estimates unavailable in the retrieved abstract.

### \cite{waite2015recovery} — “Self-Compassion and Self-Criticism in Recovery in Psychosis” (2015)

- **Methodology**: Interpretative phenomenological analysis of interviews with 10 participants.
- **Contribution**: Characterizes self-criticism as a lived “trap” within recovery.
- **Limitation**: Small qualitative sample; intended for depth rather than statistical generalization.

### \cite{kauser2021associations} — “Associations…in Adults with Cystic Fibrosis” (2021)

- **Methodology**: Cross-sectional validated questionnaires with 114 adults.
- **Contribution**: Extends the construct to chronic physical illness and quality of life.
- **Limitation**: Cross-sectional design does not establish directionality.

### \cite{pedro2019postpartum} — “Self-Criticism…Postpartum Depressive Symptoms” (2019)

- **Methodology**: Study of 686 postpartum women testing cognition mediation and compassion moderation.
- **Contribution**: Examines a specific life context rather than generic trait associations.
- **Limitation**: Temporal and causal ordering cannot be evaluated from the supplied abstract.

### \cite{paranjothy2024meta} — “Meta-Analysis of Disordered Eating…” (2024)

- **Methodology**: Meta-analysis of self-criticism, perfectionism, self-compassion, and disordered eating.
- **Contribution**: Recent quantitative synthesis of a domain where self-criticism is a proposed maintaining mechanism.
- **Limitation**: Pooled estimates and bias analyses absent from the retrieved abstract.

### \cite{longe2009neural} — “Neural Correlates of Self-Criticism and Self-Reassurance” (2009)

- **Methodology**: Neuroimaging comparison of criticism and reassurance.
- **Contribution**: Suggests these are differentiable response modes rather than simple wording variants.
- **Limitation**: Imaging task, regions, and statistics unavailable in retrieved metadata.

### \cite{chehayeb2025coregulation} — “Effects of a Co-Regulation Model for MR Teacher Training” (2025)

- **Methodology**: Mixed-reality classroom conflict, HRV, and qualitative interviews.
- **Contribution**: Recent HCI example combining a demanding simulation with self-compassion indicators.
- **Limitation**: Correlational, preprint evidence; sample and effect estimates not reported in abstract.

### \cite{poon2026body} — “Body Composition Measures That Correlate with Self-Compassion” (2026)

- **Methodology**: Canonical correlation analysis in 156 college students.
- **Contribution**: Illustrates the expanding use of sensed/biometric correlates.
- **Limitation**: Peripheral to the subsection and unsuitable for causal or diagnostic claims.

### \cite{jorke2025bloom} — “Bloom: Designing for LLM-Augmented Behavior Change Interactions” (2025)

- **Methodology**: Red-teaming plus four-week randomized field study (N=54).
- **Contribution**: Reports psychological shifts including self-compassion, while showing no descriptive short-term activity advantage for the LLM condition.
- **Limitation**: Preprint, short duration, and small sample.

### \cite{zhu2026kriya} — “Designing KRIYA” (2026)

- **Methodology**: Semi-structured interviews with 18 students using hypothetical personal data.
- **Contribution**: Frames AI-data interaction as co-interpretation and shows emotional framing can feel supportive or pressuring.
- **Limitation**: Hypothetical data and small student sample limit ecological validity.

### \cite{neff2003alternative} — “Self-Compassion: An Alternative Conceptualization…” (2003)

- **Type**: Foundational conceptual paper.
- **Contribution**: Defines self-kindness, common humanity, and mindfulness in contrast to judgment, isolation, and overidentification.
- **Limitation**: Conceptual foundation, not an intervention-effect study.

### \cite{breines2012motivation} — “Self-Compassion Increases Self-Improvement Motivation” (2012)

- **Methodology**: Four experiments spanning personal weakness, moral transgression, and test performance.
- **Contribution**: Directly counters the claim that compassion necessarily produces complacency.
- **Limitation**: The retrieved abstract does not establish durability or real-world behavior change.

### \cite{neff2023theory} — “Self-Compassion: Theory, Method, Research, and Intervention” (2023)

- **Type**: Annual Review synthesis.
- **Contribution**: Integrates the six-component model, measurement debates, outcomes, and interventions.
- **Limitation**: Narrative review coverage and evidence appraisal cannot be fully evaluated from the abstract alone.

## BibTeX Bibliography

Save the entries below to a `.bib` file and cite them from LaTeX using the keys shown above.

```bibtex
@article{lopez2015reconsideration,
  author  = {López, Angélica and Sanderman, Robbert and Smink, Ans and Zhang, Ying and van Sonderen, Eric},
  title   = {A Reconsideration of the Self-Compassion Scale's Total Score: Self-Compassion versus Self-Criticism},
  journal = {PLoS ONE},
  year    = {2015},
  doi     = {10.1371/journal.pone.0132940},
  url     = {https://doi.org/10.1371/journal.pone.0132940}
}

@article{killham2018women,
  author  = {Killham, Margo E. and Mosewich, Amber D. and Mack, Diane E. and Gunnell, Katie E. and Ferguson, Leah J.},
  title   = {Women Athletes' Self-Compassion, Self-Criticism, and Perceived Sport Performance},
  journal = {Sport, Exercise, and Performance Psychology},
  year    = {2018},
  doi     = {10.1037/spy0000127},
  url     = {https://doi.org/10.1037/spy0000127}
}

@article{gilbert2011fears,
  author  = {Gilbert, Paul and McEwan, Kirsten and Gibbons, Lucy and Chotai, Shivani and Duarte, Joana},
  title   = {Fears of Compassion and Happiness in Relation to Alexithymia, Mindfulness, and Self-Criticism},
  journal = {Psychology and Psychotherapy: Theory, Research and Practice},
  year    = {2011},
  doi     = {10.1111/j.2044-8341.2011.02046.x},
  url     = {https://doi.org/10.1111/j.2044-8341.2011.02046.x}
}

@article{ehret2014examining,
  author  = {Ehret, Anna M. and Joormann, Jutta and Berking, Matthias},
  title   = {Examining Risk and Resilience Factors for Depression: The Role of Self-Criticism and Self-Compassion},
  journal = {Cognition \& Emotion},
  year    = {2014},
  doi     = {10.1080/02699931.2014.992394},
  url     = {https://doi.org/10.1080/02699931.2014.992394}
}

@article{kelly2016within,
  author  = {Kelly, Allison C. and Tasca, Giorgio A.},
  title   = {Within-Persons Predictors of Change During Eating Disorders Treatment: An Examination of Self-Compassion, Self-Criticism, Shame, and Eating Disorder Symptoms},
  journal = {International Journal of Eating Disorders},
  year    = {2016},
  doi     = {10.1002/eat.22527},
  url     = {https://doi.org/10.1002/eat.22527}
}

@article{luoma2015shame,
  author  = {Luoma, Jason B. and Platt, Melissa},
  title   = {Shame, Self-Criticism, Self-Stigma, and Compassion in Acceptance and Commitment Therapy},
  journal = {Current Opinion in Psychology},
  year    = {2015},
  doi     = {10.1016/j.copsyc.2014.12.016},
  url     = {https://doi.org/10.1016/j.copsyc.2014.12.016}
}

@misc{gilbert2008adolescence,
  author       = {Gilbert, Paul and Irons, Chris},
  title        = {Shame, Self-Criticism, and Self-Compassion in Adolescence},
  year         = {2008},
  howpublished = {Book chapter},
  doi          = {10.1017/CBO9780511551963.011},
  url          = {https://doi.org/10.1017/CBO9780511551963.011}
}

@article{joeng2015mediators,
  author  = {Joeng, Ju Ri and Turner, Sherri L.},
  title   = {Mediators Between Self-Criticism and Depression: Fear of Compassion, Self-Compassion, and Importance to Others},
  journal = {Journal of Counseling Psychology},
  year    = {2015},
  doi     = {10.1037/cou0000071},
  url     = {https://doi.org/10.1037/cou0000071}
}

@article{gilbert2010fears,
  author  = {Gilbert, Paul and McEwan, Kirsten and Matos, Marcela and Rivis, Amanda},
  title   = {Fears of Compassion: Development of Three Self-Report Measures},
  journal = {Psychology and Psychotherapy: Theory, Research and Practice},
  year    = {2010},
  doi     = {10.1348/147608310X526511},
  url     = {https://doi.org/10.1348/147608310X526511}
}

@article{wakelin2021effectiveness,
  author  = {Wakelin, Katherine and Perman, Gemma and Simonds, Laura M.},
  title   = {Effectiveness of Self-Compassion-Related Interventions for Reducing Self-Criticism: A Systematic Review and Meta-Analysis},
  journal = {Clinical Psychology \& Psychotherapy},
  year    = {2021},
  doi     = {10.1002/cpp.2586},
  url     = {https://doi.org/10.1002/cpp.2586}
}

@article{gilbert2009introducing,
  author  = {Gilbert, Paul},
  title   = {Introducing Compassion-Focused Therapy},
  journal = {Advances in Psychiatric Treatment},
  year    = {2009},
  doi     = {10.1192/apt.bp.107.005264},
  url     = {https://doi.org/10.1192/apt.bp.107.005264}
}

@article{ondrejkova2022prevalence,
  author  = {Ondrejková, Natália and Halamová, Júlia},
  title   = {Prevalence of Compassion Fatigue Among Helping Professions and Relationship to Compassion for Others, Self-Compassion and Self-Criticism},
  journal = {Health \& Social Care in the Community},
  year    = {2022},
  doi     = {10.1111/hsc.13741},
  url     = {https://doi.org/10.1111/hsc.13741}
}

@article{neff2015scale,
  author  = {Neff, Kristin D.},
  title   = {The Self-Compassion Scale Is a Valid and Theoretically Coherent Measure of Self-Compassion},
  journal = {Mindfulness},
  year    = {2015},
  doi     = {10.1007/s12671-015-0479-3},
  url     = {https://doi.org/10.1007/s12671-015-0479-3}
}

@article{falconer2014embodying,
  author  = {Falconer, Caroline J. and Slater, Mel and Rovira, Aitor and King, John A. and Gilbert, Paul},
  title   = {Embodying Compassion: A Virtual Reality Paradigm for Overcoming Excessive Self-Criticism},
  journal = {PLoS ONE},
  year    = {2014},
  doi     = {10.1371/journal.pone.0111933},
  url     = {https://doi.org/10.1371/journal.pone.0111933}
}

@article{gilbert2006compassionate,
  author  = {Gilbert, Paul and Procter, Sue},
  title   = {Compassionate Mind Training for People with High Shame and Self-Criticism: Overview and Pilot Study of a Group Therapy Approach},
  journal = {Clinical Psychology \& Psychotherapy},
  year    = {2006},
  doi     = {10.1002/cpp.507},
  url     = {https://doi.org/10.1002/cpp.507}
}

@article{barnard2011conceptualizations,
  author  = {Barnard, Laura K. and Curry, John F.},
  title   = {Self-Compassion: Conceptualizations, Correlates, \& Interventions},
  journal = {Review of General Psychology},
  year    = {2011},
  doi     = {10.1037/a0025754},
  url     = {https://doi.org/10.1037/a0025754}
}

@article{xavier2016nonsuicidal,
  author  = {Xavier, Ana and Pinto-Gouveia, José and Cunha, Marina},
  title   = {Non-Suicidal Self-Injury in Adolescence: The Role of Shame, Self-Criticism and Fear of Self-Compassion},
  journal = {Child \& Youth Care Forum},
  year    = {2016},
  doi     = {10.1007/s10566-016-9346-1},
  url     = {https://doi.org/10.1007/s10566-016-9346-1}
}

@article{falconer2015mood,
  author  = {Falconer, Caroline J. and King, John A. and Brewin, Chris R.},
  title   = {Demonstrating Mood Repair with a Situation-Based Measure of Self-Compassion and Self-Criticism},
  journal = {Psychology and Psychotherapy: Theory, Research and Practice},
  year    = {2015},
  doi     = {10.1111/papt.12056},
  url     = {https://doi.org/10.1111/papt.12056}
}

@article{yamaguchi2014effects,
  author  = {Yamaguchi, Ayano and Kim, Min-Sun and Akutsu, Satoshi},
  title   = {The Effects of Self-Construals, Self-Criticism, and Self-Compassion on Depressive Symptoms},
  journal = {Personality and Individual Differences},
  year    = {2014},
  doi     = {10.1016/j.paid.2014.03.013},
  url     = {https://doi.org/10.1016/j.paid.2014.03.013}
}

@article{zhang2017selfcriticism,
  author  = {Zhang, Huaiyu and Watson-Singleton, Natalie N. and Pollard, Sara E. and Pittman, Delishia M. and Lamis, Dorian A.},
  title   = {Self-Criticism and Depressive Symptoms: Mediating Role of Self-Compassion},
  journal = {OMEGA---Journal of Death and Dying},
  year    = {2017},
  doi     = {10.1177/0030222817729609},
  url     = {https://doi.org/10.1177/0030222817729609}
}

@article{ferrari2019interventions,
  author  = {Ferrari, Madeleine and Hunt, Caroline and Harrysunker, Ashish and Abbott, Maree J. and Beath, Alissa P.},
  title   = {Self-Compassion Interventions and Psychosocial Outcomes: A Meta-Analysis of Randomized Controlled Trials},
  journal = {Mindfulness},
  year    = {2019},
  doi     = {10.1007/s12671-019-01134-6},
  url     = {https://doi.org/10.1007/s12671-019-01134-6}
}

@article{gilbert2017engagement,
  author  = {Gilbert, Paul and Catarino, Francisca and Duarte, Cristiana and Matos, Marcela and Kolts, Russell L.},
  title   = {The Development of Compassionate Engagement and Action Scales for Self and Others},
  journal = {Journal of Compassionate Health Care},
  year    = {2017},
  doi     = {10.1186/s40639-017-0033-3},
  url     = {https://doi.org/10.1186/s40639-017-0033-3}
}

@article{naismith2019abuse,
  author  = {Naismith, Iona and Zarate Guerrero, Santiago and Feigenbaum, Janet},
  title   = {Abuse, Invalidation, and Lack of Early Warmth Show Distinct Relationships with Self-Criticism, Self-Compassion, and Fear of Self-Compassion in Personality Disorder},
  journal = {Clinical Psychology \& Psychotherapy},
  year    = {2019},
  doi     = {10.1002/cpp.2357},
  url     = {https://doi.org/10.1002/cpp.2357}
}

@article{beaumont2016training,
  author  = {Beaumont, Elaine and Irons, Chris and Rayner, Gillian and Dagnall, Neil},
  title   = {Does Compassion-Focused Therapy Training for Health Care Educators and Providers Increase Self-Compassion and Reduce Self-Persecution and Self-Criticism?},
  journal = {Journal of Continuing Education in the Health Professions},
  year    = {2016},
  doi     = {10.1097/CEH.0000000000000023},
  url     = {https://doi.org/10.1097/CEH.0000000000000023}
}

@article{neff2008selfcompassion,
  author  = {Neff, Kristin D. and Vonk, Roos},
  title   = {Self-Compassion Versus Global Self-Esteem: Two Different Ways of Relating to Oneself},
  journal = {Journal of Personality},
  year    = {2008},
  doi     = {10.1111/j.1467-6494.2008.00537.x},
  url     = {https://doi.org/10.1111/j.1467-6494.2008.00537.x}
}

@article{krieger2018internet,
  author  = {Krieger, Tobias and Reber, Fabienne and von Glutz, Barbara and Urech, Antoine and Moser, Christian T.},
  title   = {An Internet-Based Compassion-Focused Intervention for Increased Self-Criticism: A Randomized Controlled Trial},
  journal = {Behavior Therapy},
  year    = {2018},
  doi     = {10.1016/j.beth.2018.08.003},
  url     = {https://doi.org/10.1016/j.beth.2018.08.003}
}

@article{monteromarin2016selfcriticism,
  author  = {Montero-Marín, Jesús and Gaete, Jorge and Demarzo, Marcelo and Rodero, Baltasar and Serrano Lopez, Luiz C.},
  title   = {Self-Criticism: A Measure of Uncompassionate Behaviors Toward the Self, Based on the Negative Components of the Self-Compassion Scale},
  journal = {Frontiers in Psychology},
  year    = {2016},
  doi     = {10.3389/fpsyg.2016.01281},
  url     = {https://doi.org/10.3389/fpsyg.2016.01281}
}

@article{kaurin2018buffers,
  author  = {Kaurin, Aleksandra and Schönfelder, Sandra and Wessa, Michèle},
  title   = {Self-Compassion Buffers the Link Between Self-Criticism and Depression in Trauma-Exposed Firefighters},
  journal = {Journal of Counseling Psychology},
  year    = {2018},
  doi     = {10.1037/cou0000275},
  url     = {https://doi.org/10.1037/cou0000275}
}

@article{kotera2019therapeutic,
  author  = {Kotera, Yasuhiro and Green, Pauline and Sheffield, David},
  title   = {Mental Health of Therapeutic Students: Relationships with Attitudes, Self-Criticism, Self-Compassion, and Caregiver Identity},
  journal = {British Journal of Guidance \& Counselling},
  year    = {2019},
  doi     = {10.1080/03069885.2019.1704683},
  url     = {https://doi.org/10.1080/03069885.2019.1704683}
}

@article{hermanto2016ability,
  author  = {Hermanto, Nicola and Zuroff, David C. and Kopala-Sibley, Daniel C. and Kelly, Allison C. and Matos, Marcela},
  title   = {Ability to Receive Compassion from Others Buffers the Depressogenic Effect of Self-Criticism: A Cross-Cultural Multi-Study Analysis},
  journal = {Personality and Individual Differences},
  year    = {2016},
  doi     = {10.1016/j.paid.2016.04.055},
  url     = {https://doi.org/10.1016/j.paid.2016.04.055}
}

@article{waite2015recovery,
  author  = {Waite, Felicity and Knight, Matthew T. D. and Lee, Deborah},
  title   = {Self-Compassion and Self-Criticism in Recovery in Psychosis: An Interpretative Phenomenological Analysis Study},
  journal = {Journal of Clinical Psychology},
  year    = {2015},
  doi     = {10.1002/jclp.22211},
  url     = {https://doi.org/10.1002/jclp.22211}
}

@article{kauser2021associations,
  author  = {Kauser, Sophia and Keyte, Rebecca and Regan, A. and Nash, E. F. and Fitch, G.},
  title   = {Exploring Associations Between Self-Compassion, Self-Criticism, Mental Health, and Quality of Life in Adults with Cystic Fibrosis: Informing Future Interventions},
  journal = {Journal of Clinical Psychology in Medical Settings},
  year    = {2021},
  doi     = {10.1007/s10880-021-09831-y},
  url     = {https://doi.org/10.1007/s10880-021-09831-y}
}

@article{pedro2019postpartum,
  author  = {Pedro, Liliana Maria Rodrigues and Branquinho, Mariana and Canavarro, María Cristina and Fonseca, Ana},
  title   = {Self-Criticism, Negative Automatic Thoughts and Postpartum Depressive Symptoms: The Buffering Effect of Self-Compassion},
  journal = {Journal of Reproductive and Infant Psychology},
  year    = {2019},
  doi     = {10.1080/02646838.2019.1597969},
  url     = {https://doi.org/10.1080/02646838.2019.1597969}
}

@article{paranjothy2024meta,
  author  = {Paranjothy, Sarah Marie and Wade, Tracey},
  title   = {A Meta-Analysis of Disordered Eating and Its Association with Self-Criticism and Self-Compassion},
  journal = {International Journal of Eating Disorders},
  year    = {2024},
  doi     = {10.1002/eat.24166},
  url     = {https://doi.org/10.1002/eat.24166}
}

@article{longe2009neural,
  author  = {Longe, Olivia and Maratos, Frances A. and Gilbert, Paul and Evans, Gaynor and Volker, Faye},
  title   = {Having a Word with Yourself: Neural Correlates of Self-Criticism and Self-Reassurance},
  journal = {NeuroImage},
  year    = {2009},
  doi     = {10.1016/j.neuroimage.2009.09.019},
  url     = {https://doi.org/10.1016/j.neuroimage.2009.09.019}
}

@misc{chehayeb2025coregulation,
  author        = {Chehayeb, Lara and Olszynska, Katarzyna and Bhuvaneshwara, Chirag and Tsovaltzi, Dimitra},
  title         = {Effects of a Co-Regulation Model for {MR} Teacher Training: {HRV} and Self-Compassion as Indicators of Emotion Regulation},
  year          = {2025},
  eprint        = {2502.15383},
  archivePrefix = {arXiv},
  primaryClass  = {cs.HC},
  url           = {https://arxiv.org/abs/2502.15383}
}

@misc{poon2026body,
  author        = {Poon, Enerson and Fudolig, Mikaela Irene and Hidalgo, Johanna E. and Loftness, Bryn C. and Stanton, Kathryn and Tompkins, Connie L. and Bloomfield, Laura S. P. and Price, Matthew and Dodds, Peter Sheridan and Danforth, Christopher M. and Cheney, Nick},
  title         = {Identifying Body Composition Measures That Correlate with Self-Compassion and Social Support},
  year          = {2026},
  eprint        = {2602.18467},
  archivePrefix = {arXiv},
  primaryClass  = {cs.CY},
  url           = {https://arxiv.org/abs/2602.18467}
}

@misc{jorke2025bloom,
  author        = {Jörke, Matthew and Genç, Defne and Teutschbein, Valentin and Sapkota, Shardul and Chung, Sarah and Schmiedmayer, Paul and Campero, Maria Ines and King, Abby C. and Brunskill, Emma and Landay, James A.},
  title         = {{Bloom}: Designing for {LLM}-Augmented Behavior Change Interactions},
  year          = {2025},
  eprint        = {2510.05449},
  archivePrefix = {arXiv},
  primaryClass  = {cs.HC},
  url           = {https://arxiv.org/abs/2510.05449}
}

@misc{zhu2026kriya,
  author        = {Zhu, Shanshan and Song, Wenxuan and Shi, Jiayue Melissa and Yoo, Dong Whi and Bhat, Karthik S. and Saha, Koustuv},
  title         = {Designing {KRIYA}: An {AI} Companion for Wellbeing Self-Reflection},
  year          = {2026},
  eprint        = {2601.14589},
  archivePrefix = {arXiv},
  primaryClass  = {cs.HC},
  url           = {https://arxiv.org/abs/2601.14589}
}

@article{neff2003alternative,
  author  = {Neff, Kristin D.},
  title   = {Self-Compassion: An Alternative Conceptualization of a Healthy Attitude Toward Oneself},
  journal = {Self and Identity},
  year    = {2003},
  doi     = {10.1080/15298860309032},
  url     = {https://doi.org/10.1080/15298860309032}
}

@article{breines2012motivation,
  author  = {Breines, Juliana G. and Chen, Serena},
  title   = {Self-Compassion Increases Self-Improvement Motivation},
  journal = {Personality and Social Psychology Bulletin},
  year    = {2012},
  doi     = {10.1177/0146167212445599},
  url     = {https://doi.org/10.1177/0146167212445599}
}

@article{neff2023theory,
  author  = {Neff, Kristin D.},
  title   = {Self-Compassion: Theory, Method, Research, and Intervention},
  journal = {Annual Review of Psychology},
  year    = {2023},
  volume  = {74},
  pages   = {193--218},
  doi     = {10.1146/annurev-psych-032420-031047},
  url     = {https://doi.org/10.1146/annurev-psych-032420-031047}
}
```
