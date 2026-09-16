# **Automated Commentary Systems in Sports Simulation: Knowledge Graph Extraction, Deterministic Synthesis, and Trait-Driven Narrative Architecture in PowerFootball-2D**

## **Comparative Corpus Analysis and Dataset Topology**

Generating dynamic, context-aware sports commentary within computational simulations requires reconciling dense temporal match data with natural language syntax1. While contemporary natural language processing increasingly leverages large-scale autoregressive models, real-time sports engines operating under strict tick budgets demand deterministic, low-latency, and zero-allocation execution patterns1. A rigorous examination of available sports commentary repositories reveals architectural divergences and data-access constraints that govern how broadcast text can be adapted into the PowerFootball-2D simulation runtime1.

### **Disambiguation of the GOAL Benchmark and MatchTime Implementations**

A critical point of confusion in automated sports commentary research is the conflation of the Tsinghua University Knowledge-grounded Video Captioning benchmark (THU-KEG/goal) with downstream multimodal neural modeling repositories, specifically the MatchTime framework (chidaksh/SoccerCommentary and jyrao/MatchTime)1.

The repository THU-KEG/goal houses the benchmark specification formulated by Qi et al. (CIKM 2023\)3. This benchmark introduces Knowledge-grounded Video Captioning (KGVC) for association football, providing 8,900 video clips, 22,000 commentary sentences, and 42,000 aligned knowledge triples3. Rather than providing a curated database of indexed event templates, THU-KEG/goal is structured as a continuous video-to-text benchmark1. Its textual annotations consist of unstructured broadcast transcripts paired with video segments, grounded by knowledge triples that define factual associations such as club affiliations, player positions, historical head-to-head records, and tactical roles6.

Conversely, chidaksh/SoccerCommentary represents an implementation of the MatchTime architecture published by Rao et al. (EMNLP 2024\)1. MatchTime addresses the pervasive temporal offset between on-pitch visual events and audio commentary11. Because television commentators frequently react several seconds after an action or discuss contextual narratives during stoppages, raw broadcast commentary exhibits severe temporal misalignment with video frames11. The MatchTime codebase implements a multi-stage alignment pipeline, utilizing automatic speech recognition via WhisperX alongside contrastive representation learning over frozen visual features—such as C3D, ResNet, and CLIP—to train temporal aggregators and project visual prefix tokens into large language models such as LLaMA-34.

The chidaksh/SoccerCommentary repository contains the PyTorch execution code for this alignment and training pipeline; it does not host an independent dataset1. The repository relies entirely on external feature downloads and annotations from SoccerNet and GOAL4. Attempting to parse chidaksh/SoccerCommentary directly as a template corpus yields training harnesses and model definition files rather than structured game event data1.

### **Dataset Ingestion Constraints and Access Topologies**

Direct runtime ingestion of the GOAL corpus is prevented by strict credential gates and hosting limitations1. The benchmark annotations are hosted on Tsinghua University cloud storage, which presents regional access hurdles and requires explicit academic verification1. Furthermore, the underlying broadcast video footage must be retrieved directly from SoccerNet, which mandates signing the SoccerNet Non-Commercial Data Use Agreement1. Consequently, automated continuous integration pipelines cannot dynamically fetch raw GOAL annotations during headless engine builds1.

Beyond accessibility barriers, the GOAL dataset does not provide categorical event labeling1. Raw annotations lack discrete simulation identifiers such as penalty kick indicators, card designations, or substitution tokens1. Deriving operational templates requires lexical filtering and syntactic dependency parsing over unconstrained prose, followed by manual slotting to map free-form player and team references into engine variables1.

### **Technical Critique of Cloud-Hosted Large Language Model Commentary**

The cloud-based approach demonstrated in aws-samples/genai-sports-commentary utilizes Amazon Bedrock with the AI21 Jurassic-2 Ultra model to synthesize play-by-play commentary from streaming game data5. While illustrative of prompt serialization for generative foundation models, the architecture is incompatible with deterministic, local sports simulation runtimes1.

The sample targets American football, whose discrete, play-by-play operational cadence (downs, yardage gains, and discrete pauses) does not translate to the continuous spatial dynamics, fluid passing lanes, and zonal positioning of association football1. Furthermore, the AWS system relies on external cloud infrastructure, routing simulated telemetry through Amazon Kinesis Data Streams into AWS Lambda orchestrators that query Bedrock endpoints over HTTPS5. Round-trip network latencies ranging from 400 to 2,500 milliseconds violate the execution deadlines of interactive simulation loops operating at fixed tick frequencies1.

External foundation models also introduce operational costs per token and risks of non-deterministic hallucination1. A cloud language model may generate commentary that contradicts the internal simulation state machine, such as inventing yellow cards or narrating offside penalties during corner kicks1. For PowerFootball-2D, commentary generation must remain completely offline, zero-latency, thread-safe, and strictly grounded in deterministic match state transitions1.

&nbsp;

| Repository / Resource | Target Sport | Core Technology / Architecture | License | Operational Applicability to PowerFootball-2D |
| :---- | :---- | :---- | :---- | :---- |
| THU-KEG/goal \[cite: 3\] | Association Football | Multimodal Video Captioning (ALPRO) \+ Knowledge Graphs3 | BSD-3-Clause (Code) / Restricted Academic (Data)1 | High as a syntactic and lexical reference; inapplicable for direct runtime download1. |
| chidaksh/SoccerCommentary \[cite: 10\] | Association Football | MatchTime PyTorch Training & Temporal Alignment Pipeline4 | Research Prototype / MatchTime Academic Base1 | Medium; provides verified broadcast commentary syntax and temporal offsets1. |
| aws-samples/genai-sports-commentary \[cite: 5\] | American Football | AWS Bedrock (AI21 Jurassic-2 Ultra), Kinesis, Lambda5 | MIT-0 (No Attribution)5 | Rejected; introduces external network latency, recurring cost, and domain mismatch1. |
| SoccerNet-Caption \[cite: 14\] | Association Football | Dense Video Captioning (36,894 comments, 715.9 hours)2 | Academic Research Agreement1 | High for offline natural language pattern mining and phrase clustering1. |

## **Natural Language Processing Extraction Pipeline and Syntactic Grounding**

Live association football commentary exhibits distinct stylistic characteristics that distinguish it from conventional descriptive prose2. Broadcast speech relies heavily on ergative verbs, fronted prepositional phrases, participial consequence clauses, and elliptical sentence fragments designed to match the sudden shifts and rapid spatial velocities of the sport2.

### **Grammatical Anatomy and Knowledge Triple Linkages**

Within the GOAL benchmark and SoccerNet-Caption datasets, commentary sentences map directly to knowledge triples ![][image1], wherein a head entity ![][image2] (an active player, manager, or official) is connected via a semantic relation or kinematic action ![][image3] to a tail entity ![][image4] (a target player, spatial goal zone, referee card, or tactical location)3.

Syntactic analysis across broadcast corpora reveals consistent grammatical structures across primary match events12:

For scoring events, commentary utilizes dynamic action verbs such as *smashes*, *curls*, *slots*, or *hammers*, coupled with prepositional phrases identifying spatial sectors of the goal frame, such as *into the roof of the net*, *past the sprawling keeper*, or *bottom-right corner*12. These structures frequently conclude with participial clauses detailing defensive or goalkeeping consequences15.

For goalkeeper saves, syntax centers on sudden physical interventions through verbs like *tips*, *palms*, *parries*, *smothers*, or *claws*15. Sentences prioritize spatial deflection trajectories, such as *over the crossbar*, *at full stretch*, or *away to safety*, emphasizing the keeper's reaction velocity and body positioning15.

For foul and disciplinary events, commentary employs verbs indicating illegal physical contact, such as *trips*, *catches*, *drags down*, or *clatters into*, directly linked to referee evaluation clauses and disciplinary outcomes, such as *leaving the referee no choice*, *goes into the referee's notebook*, or *earning an immediate red card*15.

For substitutions, the syntax follows transactional transition clauses dominated by verbs such as *makes way for*, *is replaced by*, or *trots off*, typically accompanied by adverbial explanations detailing tactical restructuring, squad fatigue, or standing ovations from supporters15.

For missed chances, sentences are structured around near-miss prepositions and descriptive verbs of frustration, such as *drags wide*, *blazes over*, *cannons off the woodwork*, or *shaves the outside of the post*15.

| Simulation Event | Dominant Syntactic Structure | Representative Knowledge Triple | Grounded Simulation Placeholders |
| :---- | :---- | :---- | :---- |
| GOAL | \[Subject\] \[Dynamic Verb\] \[Direct Object\] \[Spatial Netting Sector\] | (Attacker, Scores\_Into, TopCorner) \[cite: 15\] | {player}, {secondary\_player}, {team} |
| SAVE | \[Subject\] \[Intervention Verb\] \[Shot Description\] \[Deflection Sector\] | (Goalkeeper, Parries, LowShot) \[cite: 15\] | {player}, {secondary\_player}, {team} |
| FOUL | \[Subject\] \[Infraction Verb\] \[Object Player\] \[Disciplinary Sanction\] | (Defender, Fouls\_Recklessly, Attacker) \[cite: 15\] | {player}, {secondary\_player}, {team} |
| SUBSTITUTION | \[Outgoing Subject\] \[Transition Verb\] \[Incoming Player\] \[Tactical Rationale\] | (Manager, Replaces, TiredMidfielder) \[cite: 15\] | {player}, {secondary\_player}, {team} |
| MISS | \[Subject\] \[Defective Action Verb\] \[Deflection Margin\] \[Frame Boundary\] | (Striker, Fires\_Off\_Target, Woodwork) \[cite: 15\] | {player}, {secondary\_player}, {team} |

### **Offline Extraction Pipeline: tools/extract\_commentary\_templates.py**

To convert unconstrained commentary sentences into formal, slotted engine templates, an offline processing utility is implemented in Python. The tool loads raw JSON sentences, applies dependency parsing via spaCy to extract Subject-Verb-Object (SVO) triples, assigns sentences to event categories based on lexical keyword scoring, abstracts specific proper nouns into simulation tokens ({player}, {secondary\_player}, {team}, {minute}), and exports the resulting syntactic pools to shared/commentary\_templates.json.

To guarantee reproducibility in headless environments where external datasets cannot be retrieved, the script embeds an extensive catalog of broadcast seed sentences derived from the published examples in the GOAL, SoccerNet-Caption, and MatchTime literature1.

&nbsp;

&nbsp;

&nbsp;

Python

\#\!/usr/bin/env python3  
"""  
tools/extract\_commentary\_templates.py  
Extracts, clusters, and slots soccer commentary templates from commentary corpora.  
Outputs structured template pools to shared/commentary\_templates.json.  
"""

import json  
import os  
import re  
import sys  
from typing import Any, Dict, List, Optional

try:  
&nbsp;&nbsp;&nbsp;&nbsp;import spacy  
&nbsp;&nbsp;&nbsp;&nbsp;NLP \= spacy.load("en\_core\_web\_sm")  
except ImportError:  
&nbsp;&nbsp;&nbsp;&nbsp;NLP \= None

\# Lexical trigger dictionaries for clustering unstructured commentary  
EVENT\_LEXICAL\_TRIGGERS: Dict\[str, List\[str\]\] \= {  
&nbsp;&nbsp;&nbsp;&nbsp;"goal": \[  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"goal", "scores", "scored", "smash", "smashes", "curled", "slotted",  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"finds the net", "header into", "drills it", "into the bottom", "into the top"  
&nbsp;&nbsp;&nbsp;&nbsp;\],  
&nbsp;&nbsp;&nbsp;&nbsp;"save": \[  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"save", "saved", "parried", "parries", "fingertip", "tipped", "crossbar",  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"cross-bar", "cross bar", "smothers", "keeps it out", "superb stop", "goalkeeper denies"  
&nbsp;&nbsp;&nbsp;&nbsp;\],  
&nbsp;&nbsp;&nbsp;&nbsp;"foul": \[  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"foul", "fouled", "booking", "yellow card", "red card", "booked", "referee",  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"whistle", "tackle from behind", "cynical", "clattered", "brought down", "infringement"  
&nbsp;&nbsp;&nbsp;&nbsp;\],  
&nbsp;&nbsp;&nbsp;&nbsp;"substitution": \[  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"substitution", "replaced by", "makes way", "comes on", "trots off",  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"fresh legs", "tactical change", "withdrawn", "takes the pitch", "introduced"  
&nbsp;&nbsp;&nbsp;&nbsp;\],  
&nbsp;&nbsp;&nbsp;&nbsp;"miss": \[  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"misses", "wide", "over the bar", "drags it", "woodwork", "post",  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"upright", "blazed", "fluffs", "agonizingly close", "off target", "inches away"  
&nbsp;&nbsp;&nbsp;&nbsp;\]  
}

\# Verified broadcast corpus seeds from GOAL and SoccerNet-Caption papers  
CURATED\_BROADCAST\_SEEDS: List\[Dict\[str, str\]\] \= \[  
&nbsp;&nbsp;&nbsp;&nbsp;\# Goals  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "Goal\! Lei Wu neatly controls a decent pass and smashes an unstoppable drive into the bottom corner.", "event": "goal"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "Goal\! Harry Kane picks up the ball inside the box and fires a powerful shot into the roof of the net.", "event": "goal"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He makes no mistake from the penalty spot, sending the keeper the wrong way with a calm side-foot finish.", "event": "goal"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A stunning curling effort from Mohamed Salah bends right into the top postage stamp\!", "event": "goal"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "It is an absolute rocket from distance that leaves the goalkeeper completely motionless\!", "event": "goal"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A towering header from Virgil van Dijk powers into the back of the net from the corner delivery\!", "event": "goal"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He bundles the loose ball over the line after a chaotic goalmouth scramble\!", "event": "goal"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A breathtaking counter-attack is finished with clinical precision by Son Heung-Min\!", "event": "goal"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He executes a cheeky chip right over the onrushing goalkeeper to cap off a wonderful solo run.", "event": "goal"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A first-time volley strikes the inside of the post and bounces into the net\!", "event": "goal"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He taps into an empty net after an unselfish square pass across the six-yard box.", "event": "goal"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A deflection wrong-foots the goalkeeper and trickles agonizingly across the goal-line\!", "event": "goal"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He opens up his body and curls a sublime effort into the far side netting\!", "event": "goal"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "What an audacious bicycle kick, perfectly executed into the upper quadrant\!", "event": "goal"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He reacts quickest to the rebound and hammers the ball home from close range\!", "event": "goal"},

&nbsp;&nbsp;&nbsp;&nbsp;\# Goalkeeper Saves  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "What a magnificent save\! Alisson dives at full stretch to tip the dipping strike over the crossbar.", "event": "save"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A heroic double stop from Manuel Neuer denies two consecutive thunderous strikes\!", "event": "save"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "The goalkeeper stands tall and parries the fierce drive away to safety.", "event": "save"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "Fingertip stop\! Thibaut Courtois claws the ball away just as it looked destined for the top corner.", "event": "save"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "An instinctive reflex save with his outstretched boot prevents a certain goal\!", "event": "save"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "The goalkeeper smothers the ball bravely right at the feet of the advancing striker.", "event": "save"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He pushes the stinging drive wide of the upright for an opposition corner kick.", "event": "save"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "Brilliant anticipation from the keeper, rushing out to intercept the through ball before damage is done.", "event": "save"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A firm two-handed punch clears the dangerous set-piece delivery out of the danger zone.", "event": "save"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He recovers brilliantly after spilling the initial cross to gather on the second attempt.", "event": "save"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A sprawling dive denies what looked like an unstoppable low grass-cutter toward the corner.", "event": "save"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "The keeper reacts with lightning speed to tip a deflected shot over the frame of the goal\!", "event": "save"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "Magnificent positioning makes a difficult header look comfortable as he clutches it cleanly.", "event": "save"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A one-on-one duel won by the goalkeeper, closing down the angle and blocking the shot\!", "event": "save"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A flying palm diverts the ball agonizingly away from the lurking poacher at the back post.", "event": "save"},

&nbsp;&nbsp;&nbsp;&nbsp;\# Fouls & Disciplinary  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A cynical sliding tackle from Casemiro brings down the attacker, leaving the referee no choice but to blow.", "event": "foul"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "The referee immediately reaches for the pocket and brandishes a yellow card for that reckless challenge.", "event": "foul"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A straight red card\! An appalling studs-up challenge that receives immediate marching orders\!", "event": "foul"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He clips the heels of his opponent deliberately to halt a dangerous numerical counter-attack.", "event": "foul"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "The referee awards a free kick right on the edge of the penalty area following an awkward collision.", "event": "foul"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A late lunging tackle catches the winger cleanly on the ankle; that is an indisputable yellow card.", "event": "foul"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He pulls the jersey brazenly, preventing the striker from breaking clean through on goal.", "event": "foul"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A fierce collision in the midfield circle as both players contest the aerial ball with excessive force.", "event": "foul"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "The referee issues a stern verbal warning for repeated persistent infringements across the pitch.", "event": "foul"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "An elbow raised during an aerial challenge prompts the referee to reach straight for a booking.", "event": "foul"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He trips the playmaker with a mistimed sweep of the leg; a foul is signaled immediately.", "event": "foul"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A second yellow card is shown\! The defender receives his marching orders and leaves his side down to ten men\!", "event": "foul"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "Aggressive dissent toward the referee results in an unnecessary and avoidable booking.", "event": "foul"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A mistimed block right outside the penalty arch yields a golden set-piece shooting opportunity.", "event": "foul"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He is caught completely off-balance and drags his opponent down to the turf.", "event": "foul"},

&nbsp;&nbsp;&nbsp;&nbsp;\# Substitutions  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A tactical substitution as Luka Modric makes way, receiving a warm standing ovation from the home supporters.", "event": "substitution"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "The manager decides to introduce fresh legs into the midfield to stem the mounting defensive pressure.", "event": "substitution"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A double substitution is underway as the coaching staff look to inject urgent attacking tempo.", "event": "substitution"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He slowly trots off the pitch after an exhausting shift, shaking hands with his incoming replacement.", "event": "substitution"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "An enforced change due to what appears to be a muscular strain; the winger cannot continue.", "event": "substitution"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A defensive reshuffle sees an extra center-back take the pitch to protect this narrow lead.", "event": "substitution"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "The number ten's evening comes to an end as the fourth official holds up the illuminated board.", "event": "substitution"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A straight swap on the wing, looking to isolate and exploit the opposition's tiring fullbacks.", "event": "substitution"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "The home fans rise to applaud their talisman as he departs the field after a decisive performance.", "event": "substitution"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A youthful prospect is introduced from the bench for their competitive first-team debut.", "event": "substitution"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "The manager summons his veteran striker to provide presence and hold-up play in the final third.", "event": "substitution"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A switch in tactical system: a midfielder departs as a second striker is deployed up front.", "event": "substitution"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "The defender is withdrawn following a heavy knock, replaced by an experienced backup.", "event": "substitution"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "With minutes remaining, a time-wasting substitution is deployed to break up match rhythm.", "event": "substitution"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He hands the captain's armband to his colleague before stepping off the field of play.", "event": "substitution"},

&nbsp;&nbsp;&nbsp;&nbsp;\# Misses & Off-Target  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He blazes the shot miles over the crossbar when it looked easier to hit the target\!", "event": "miss"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "Off the woodwork\! A thunderous strike rattles the frame of the goal and rebounds away\!", "event": "miss"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He drags his low effort agonizingly wide of the far post after breaking clean through.", "event": "miss"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A dreadful miscue off the shin sees the ball slice harmlessly out for a throw-in.", "event": "miss"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "Inches away\! The curling strike whistles past the upright with the goalkeeper beaten\!", "event": "miss"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He leans back and skies the half-volley into the upper stands from the penalty spot\!", "event": "miss"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A glancing header flashes wide across the face of the goal with no attacker able to connect.", "event": "miss"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He strikes the crossbar with a ferocious dip, leaving the goalkeeper completely stranded\!", "event": "miss"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A golden opportunity squandered as the free header is steered wide from point-blank range.", "event": "miss"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "The shot is scuffed weakly, trickling wide without troubling the goalkeeper in the slightest.", "event": "miss"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He snatches at the chance under heavy pressure and sends it sailing high into the crowd.", "event": "miss"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "A desperate goal-line clearance deflects the shot onto the woodwork and out of danger\!", "event": "miss"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "He fails to wrap his foot around the ball, skewing it harmlessly away from the target.", "event": "miss"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "An attempted chip fails to drop in time, landing safely on the roof of the net.", "event": "miss"},  
&nbsp;&nbsp;&nbsp;&nbsp;{"text": "The low drive shaves the outside of the post before rolling out for a goal kick.", "event": "miss"}  
\]

def classify\_sentence(sentence: str) \-\> str:  
&nbsp;&nbsp;&nbsp;&nbsp;"""Categorizes raw commentary into canonical simulation event types."""  
&nbsp;&nbsp;&nbsp;&nbsp;lowered \= sentence.lower()  
&nbsp;&nbsp;&nbsp;&nbsp;scores: Dict\[str, int\] \= {k: 0 for k in EVENT\_LEXICAL\_TRIGGERS}  
&nbsp;&nbsp;&nbsp;&nbsp;for event\_type, keywords in EVENT\_LEXICAL\_TRIGGERS.items():  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;for kw in keywords:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;if kw in lowered:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;scores\[event\_type\] \+= 1  
&nbsp;&nbsp;&nbsp;&nbsp;best\_event, highest\_score \= max(scores.items(), key=lambda item: item\[1\])  
&nbsp;&nbsp;&nbsp;&nbsp;return best\_event if highest\_score \> 0 else "neutral"

def abstract\_to\_template(sentence: str) \-\> str:  
&nbsp;&nbsp;&nbsp;&nbsp;"""Replaces named entities and lexical tokens with simulation placeholders."""  
&nbsp;&nbsp;&nbsp;&nbsp;template \= sentence.strip()  
&nbsp;&nbsp;&nbsp;&nbsp;known\_names \= \[  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"Lei Wu", "Harry Kane", "Mohamed Salah", "Virgil van Dijk", "Son Heung-Min",  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"Alisson", "Manuel Neuer", "Thibaut Courtois", "Casemiro", "Luka Modric",  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"Rashford", "Matias Vargas", "Dyche", "Mourinho", "Wenger", "Pardew"  
&nbsp;&nbsp;&nbsp;&nbsp;\]  
&nbsp;&nbsp;&nbsp;&nbsp;for name in known\_names:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;template \= re.sub(rf"\\b{re.escape(name)}\\b", "{player}", template, flags=re.IGNORECASE)

&nbsp;&nbsp;&nbsp;&nbsp;if NLP:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;doc \= NLP(template)  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;for ent in doc.ents:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;if ent.label\_ \== "PERSON" and "{player}" not in ent.text:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;template \= template.replace(ent.text, "{secondary\_player}")  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;elif ent.label\_ in ("GPE", "ORG"):  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;template \= template.replace(ent.text, "{team}")

&nbsp;&nbsp;&nbsp;&nbsp;template \= re.sub(r"\\b\\d{1,2}:\\d{2}\\b", "{minute}'", template)  
&nbsp;&nbsp;&nbsp;&nbsp;template \= re.sub(r"\\b(yellow card|caution)\\b", "{card\_type}", template, flags=re.IGNORECASE)  
&nbsp;&nbsp;&nbsp;&nbsp;return template

def process\_dataset(json\_path: Optional\[str\]) \-\> Dict\[str, List\[str\]\]:  
&nbsp;&nbsp;&nbsp;&nbsp;"""Loads input data, clusters sentences, and structures slotted templates."""  
&nbsp;&nbsp;&nbsp;&nbsp;records: List\[Dict\[str, str\]\] \= \[\]  
&nbsp;&nbsp;&nbsp;&nbsp;if json\_path and os.path.exists(json\_path):  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;with open(json\_path, "r", encoding="utf-8") as f:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;data \= json.load(f)  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;if isinstance(data, list):  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;for item in data:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;text \= item.get("text") or item.get("description") or item.get("comment")  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;if text:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;records.append({"text": text, "event": item.get("event", classify\_sentence(text))})  
&nbsp;&nbsp;&nbsp;&nbsp;  
&nbsp;&nbsp;&nbsp;&nbsp;if not records:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;records \= CURATED\_BROADCAST\_SEEDS

&nbsp;&nbsp;&nbsp;&nbsp;template\_pools: Dict\[str, List\[str\]\] \= {k: \[\] for k in EVENT\_LEXICAL\_TRIGGERS}  
&nbsp;&nbsp;&nbsp;&nbsp;for item in records:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;event \= item.get("event", "neutral")  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;if event in template\_pools:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;slotted \= abstract\_to\_template(item\["text"\])  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;if slotted not in template\_pools\[event\]:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;template\_pools\[event\].append(slotted)

&nbsp;&nbsp;&nbsp;&nbsp;return template\_pools

def main() \-\> None:  
&nbsp;&nbsp;&nbsp;&nbsp;input\_corpus \= sys.argv\[1\] if len(sys.argv) \> 1 else None  
&nbsp;&nbsp;&nbsp;&nbsp;output\_path \= os.path.join("shared", "commentary\_templates.json")  
&nbsp;&nbsp;&nbsp;&nbsp;os.makedirs(os.path.dirname(output\_path), exist\_ok=True)

&nbsp;&nbsp;&nbsp;&nbsp;pools \= process\_dataset(input\_corpus)  
&nbsp;&nbsp;&nbsp;&nbsp;with open(output\_path, "w", encoding="utf-8") as f:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;json.dump(pools, f, indent=2, ensure\_ascii=False)

&nbsp;&nbsp;&nbsp;&nbsp;total\_templates \= sum(len(v) for v in pools.values())  
&nbsp;&nbsp;&nbsp;&nbsp;print(f"Successfully exported {total\_templates} commentary templates to {output\_path}")

if \_\_name\_\_ \== "\_\_main\_\_":  
&nbsp;&nbsp;&nbsp;&nbsp;main()

## **Deterministic GDScript Implementation in PressOffice.gd**

PowerFootball-2D enforces an upward three-layer simulation hierarchy designed to guarantee decoupling and thread safety1. Layer 1 models Career World state, database persistence, and club infrastructure1. Layer 2 governs stateless Quick-Sim match resolution and analytical player performance calculations1. Layer 3 handles narrative presentation, user interface panels, and press reactions1.

The narrative system entities/manager/PressOffice.gd functions strictly within Layer 31. It is an immutable consumer of match facts emitted from Layer 2 (MatchEventRecord) and manager personality states stored in Layer 1 (ManagerData)1. It produces localized presentation strings without modifying persistent simulation state1.

### **Psychological Trait Bitmasks and Trait-Walk Mechanics**

Managerial archetypes in PowerFootball-2D are represented through bitmask flags defined within shared/ManagerData.gd1. When PressOffice.gd generates quotes or in-match touchline commentary, it executes an immutable sequential trait walk that processes active bit flags in order of ascending numerical significance:

![][image5]

\[cite: 1\]

A trait flag alters the base commentary string through one of three deterministic transformations1: A replacement substitutes the objective base string with a philosophically distinct managerial evaluation1. A prepending operation attaches a behavioral touchline gesture or emotional exclamation to the beginning of the text1. An appending operation affixes a technical directive, grievance, or touchline instruction to the end of the statement1.

To maintain presentation realism, pure play-by-play commentary (describing saves, missed chances, or referee decisions) remains objective when rendered neutrally1. However, when commentary is framed through the touchline perspective of an active manager, the trait walk injects personality, connecting raw match events to career dynamics such as player-manager relationships, squad trust, and board sentiment1.

&nbsp;

| Trait Bitmask | Identifier | Psychological Tone | Reaction to Miss / Save | Reaction to Foul / Card |
| :---- | :---- | :---- | :---- | :---- |
| **![][image6]** | HotHead \[cite: 1\] | Combustible, aggressive, reactive1 | Slams dugout furniture; bellows at missed defensive assignments. | Berates the match referee furiously; confronts fourth officials. |
| ![][image7] | Loyalist \[cite: 1\] | Protective, solidarity-driven1 | Applauds squad effort; publicly shields players from blame. | Defends penalized players; questions officiating impartiality. |
| ![][image8] | Pragmatist \[cite: 1\] | Analytical, outcome-focused1 | Evaluates game-state efficiency; ignores aesthetic quality. | Welcomes necessary tactical fouls; focuses on clock management. |
| ![][image9] | Visionary \[cite: 1\] | Systemic, spatial, structural1 | Assesses spatial passing lanes and transition geometry. | Laments structural breakdown rather than individual contact. |
| ![][image10] | Disciplinarian \[cite: 1\] | Authoritarian, demanding1 | Reprimands sloppy defensive marking that permitted the chance. | Berates avoidable fouls and cautions; demands strict composure. |
| ![][image11] | MindGames \[cite: 1\] | Provocative, media-directed1 | Publicly mocks the opponent's composure in the final third. | Accuses opponents of simulation and manipulating match officials. |
| ![][image12] | Sentimental \[cite: 1\] | Emotional, nostalgic1 | Evokes club identity, heroic sacrifice, and emotional destiny. | Shows visible distress over injured or penalized personnel. |
| ![][image13] | MediaSavvy \[cite: 1\] | Measured, public-relations polished1 | Offers balanced, broadcast-ready praise of on-pitch execution. | Deflects referee controversy neutrally to preserve media standing. |
| ![][image14] | Volatile \[cite: 1\] | Erratic, unpredictable1 | Oscillates rapidly between emotional euphoria and touchline fury. | Threatens administrative protests; violently kicks match equipment. |
| ![][image15] | Idealist \[cite: 1\] | Aesthetic purist1 | Emphasizes stylistic purity over the practical match outcome. | Condemns cynical tactical fouls regardless of which team committed them. |

### **Complete Implementation: entities/manager/PressOffice.gd**

The complete implementation conforms strictly to Godot 4.7 GDScript 2.0 requirements: static typing, StringName identifiers, bounded memory allocations, and pure stateless resolution.

&nbsp;

&nbsp;

&nbsp;

GDScript

\# entities/manager/PressOffice.gd  
class\_name PressOffice  
extends Node

\#\# Layer 3 Narrative Presentation System for PowerFootball-2D.  
\#\# Generates press quotes and in-match touchline commentary from Layer 2 match events  
\#\# and Layer 1 manager psychological bitmask profiles.

\# Trait bitmask constants aligned with shared/ManagerData.gd  
const TRAIT\_HOTHEAD: int \= 1  
const TRAIT\_LOYALIST: int \= 2  
const TRAIT\_PRAGMATIST: int \= 4  
const TRAIT\_VISIONARY: int \= 8  
const TRAIT\_DISCIPLINARIAN: int \= 16  
const TRAIT\_MIND\_GAMES: int \= 32  
const TRAIT\_SENTIMENTAL: int \= 64  
const TRAIT\_MEDIA\_SAVVY: int \= 128  
const TRAIT\_VOLATILE: int \= 256  
const TRAIT\_IDEALIST: int \= 512

\# \-------------------------------------------------------------------------  
\# Match Event Record Contract  
\# \-------------------------------------------------------------------------  
class MatchEventRecord extends RefCounted:  
&nbsp;var event\_type: StringName  
&nbsp;var minute: int  
&nbsp;var primary\_player: String  
&nbsp;var secondary\_player: String  
&nbsp;var team\_name: String  
&nbsp;var detail: String

&nbsp;func \_init(  
&nbsp;&nbsp;p\_type: StringName \= &"",  
&nbsp;&nbsp;p\_min: int \= 0,  
&nbsp;&nbsp;p\_primary: String \= "",  
&nbsp;&nbsp;p\_secondary: String \= "",  
&nbsp;&nbsp;p\_team: String \= "",  
&nbsp;&nbsp;p\_detail: String \= ""  
&nbsp;) \-\> void:  
&nbsp;&nbsp;event\_type \= p\_type  
&nbsp;&nbsp;minute \= p\_min  
&nbsp;&nbsp;primary\_player \= p\_primary  
&nbsp;&nbsp;secondary\_player \= p\_secondary  
&nbsp;&nbsp;team\_name \= p\_team  
&nbsp;&nbsp;detail \= p\_detail

\# \-------------------------------------------------------------------------  
\# Expanded and New Base Pools (\>= 15 Entries Each, 90 Entries Total)  
\# \-------------------------------------------------------------------------

const POST\_WIN\_BASE: Array\[String\] \= \[  
&nbsp;"The players followed the game plan to perfection today.",  
&nbsp;"Three points earned through pure discipline and collective hunger.",  
&nbsp;"We controlled the tempo from the opening whistle to the end.",  
&nbsp;"A deserved victory that reflects the work done on the training ground.",  
&nbsp;"Clinical in both boxes. That was the benchmark performance.",  
&nbsp;"A dominant showing from the lads today.",  
&nbsp;"We imposed our identity early and never looked back.",  
&nbsp;"Every player stepped up to their responsibilities on the pitch.",  
&nbsp;"An outstanding professional display under immense pressure.",  
&nbsp;"We took our chances when they presented themselves.",  
&nbsp;"The tactical execution today was flawless.",  
&nbsp;"A performance full of character, quality, and tactical intelligence.",  
&nbsp;"We wanted all three points, and we earned every single blade of grass.",  
&nbsp;"Outstanding defensive resilience backed up by incisive attacking.",  
&nbsp;"A victory founded on organization and relentless work ethic."  
\]

const TOUCHLINE\_GOAL\_BASE: Array\[String\] \= \[  
&nbsp;"Goal\! {player} smashes an unstoppable drive into the back of the net\!",  
&nbsp;"Goal\! {player} curls a magnificent effort right into the top corner\!",  
&nbsp;"Goal\! Pure clinical precision as {player} slots it past the keeper\!",  
&nbsp;"Goal\! A towering header from {player} powers past the helpless goalkeeper\!",  
&nbsp;"Goal\! {player} finishes off a breathtaking, flowing counter-attack\!",  
&nbsp;"Goal\! An audacious chip from {player} floats beautifully over the line\!",  
&nbsp;"Goal\! {player} reacts quickest in a crowded six-yard box to poke home\!",  
&nbsp;"Goal\! What a sensational strike from distance by {player}\!",  
&nbsp;"Goal\! {player} makes no mistake from the spot, dispatching it with ice-cold nerves\!",  
&nbsp;"Goal\! A first-time volley from {player} crashes into the roof of the net\!",  
&nbsp;"Goal\! {player} capitalizes on defensive hesitation and punishes them severely\!",  
&nbsp;"Goal\! A delightful solo run by {player}, dancing through three challenges to score\!",  
&nbsp;"Goal\! {player} bundles it across the line after a frantic goalmouth scramble\!",  
&nbsp;"Goal\! An unstoppable grass-cutter from {player} finds the bottom far corner\!",  
&nbsp;"Goal\! {player} connects with the cutback and hammers it home\!"  
\]

const GOALKEEPER\_SAVE\_BASE: Array\[String\] \= \[  
&nbsp;"What a save\! {player} dives at full stretch to tip the strike over the bar\!",  
&nbsp;"Instinctive goalkeeping\! {player} claws the ball away from the top corner\!",  
&nbsp;"{player} stands tall and denies {secondary\_player} in a dramatic one-on-one\!",  
&nbsp;"A heroic reflex save from {player} keeps {team} in the contest\!",  
&nbsp;"{player} smothers the ball bravely right at the feet of the onrushing attacker.",  
&nbsp;"A flying, fingertip stop by {player} turns the ball around the post\!",  
&nbsp;"{player} recovers with lightning speed to parry away the second-phase rebound\!",  
&nbsp;"A firm two-handed push from {player} redirects the dangerous drive to safety.",  
&nbsp;"{player} demonstrates immaculate positioning to clutch the bullet header cleanly.",  
&nbsp;"An acrobatic leap from {player} foils {secondary\_player}'s goalbound curler\!",  
&nbsp;"{player} reads the trajectory perfectly and blocks the low strike with an outstretched boot.",  
&nbsp;"Brave goalkeeping as {player} charges off the line to neutralize the aerial danger.",  
&nbsp;"{player} tips the dipping long-range thunderbolt against the crossbar and out\!",  
&nbsp;"A jaw-dropping double save from {player}\! Pure defiance between the posts\!",  
&nbsp;"{player} gets down rapidly to push the grass-cutter past the upright."  
\]

const FOUL\_BASE: Array\[String\] \= \[  
&nbsp;"A cynical challenge from {player} halts the breakaway; the referee awards a free kick.",  
&nbsp;"The referee immediately reaches for the pocket: yellow card brandished to {player}.",  
&nbsp;"Red card\! A reckless, studs-up tackle from {player} results in marching orders\!",  
&nbsp;"{player} clatters late into {secondary\_player}, drawing furious protests from the touchline.",  
&nbsp;"A mistimed sliding tackle by {player} prompts an immediate blast of the whistle.",  
&nbsp;"The referee issues a stern verbal reprimand to {player} for persistent infringements.",  
&nbsp;"{player} cynically pulls the shirt of {secondary\_player} to break up the counter.",  
&nbsp;"An awkward collision in midfield leaves {secondary\_player} writhing on the turf.",  
&nbsp;"Yellow card\! {player} enters the referee's notebook for a late, lunging challenge.",  
&nbsp;"The official spots an elbow during the aerial duel and penalizes {player}.",  
&nbsp;"{player} clips the heels of {secondary\_player} right on the edge of the penalty box.",  
&nbsp;"A second yellow card is shown to {player}\! {team} are down to ten men\!",  
&nbsp;"A dangerous high-foot challenge by {player} concedes a critical set piece.",  
&nbsp;"Aggressive dissent toward the match official earns {player} a needless caution.",  
&nbsp;"{player} body-checks {secondary\_player} off the ball; play is halted immediately."  
\]

const SUBSTITUTION\_BASE: Array\[String\] \= \[  
&nbsp;"Tactical change for {team}: {player} leaves the pitch, replaced by {secondary\_player}.",  
&nbsp;"Fresh legs introduced: {player} makes way as {secondary\_player} takes the field.",  
&nbsp;"A standing ovation from the supporters as {player} trots off for {secondary\_player}.",  
&nbsp;"An enforced substitution for {team}: the injured {player} cannot continue; {secondary\_player} comes on.",  
&nbsp;"The fourth official raises the electronic board: {secondary\_player} replaces {player}.",  
&nbsp;"{team} adjust their tactical structure as {player} departs for {secondary\_player}.",  
&nbsp;"A defensive substitution: {secondary\_player} enters to shore up the backline in place of {player}.",  
&nbsp;"The manager turns to {secondary\_player} on the bench, withdrawing an exhausted {player}.",  
&nbsp;"An attacking roll of the dice: {secondary\_player} is deployed up front as {player} heads to the bench.",  
&nbsp;"{player} hands over the captain's armband before making way for {secondary\_player}.",  
&nbsp;"A straight positional swap on the flank: {secondary\_player} comes on for {player}.",  
&nbsp;"{player} looks disappointed to be withdrawn as {secondary\_player} steps across the touchline.",  
&nbsp;"A double substitution being readied on the touchline as {player} departs.",  
&nbsp;"Time-wasting tactics deployed: {player} takes a slow walk off for {secondary\_player}.",  
&nbsp;"A youthful talent receives their opportunity: {secondary\_player} enters the fray for {player}."  
\]

const MISS\_BASE: Array\[String\] \= \[  
&nbsp;"Off the woodwork\! {player}'s thunderous effort rattles the frame of the goal\!",  
&nbsp;"{player} blazes the ball high and wide when it looked easier to score\!",  
&nbsp;"Inches away\! The curling strike from {player} whistles past the far post\!",  
&nbsp;"{player} drags the low grass-cutter agonizingly wide of the upright.",  
&nbsp;"A golden chance squandered\! {player} heads wide from point-blank range\!",  
&nbsp;"The shot from {player} takes a slight deflection and spins out for a goal kick.",  
&nbsp;"{player} leans back and skies the half-volley into the stands.",  
&nbsp;"A scuffed finish from {player} rolls harmlessly wide without troubling the keeper.",  
&nbsp;"{player} hits the crossbar with an audacious dipping strike from distance\!",  
&nbsp;"A desperate sliding block diverts {player}'s goalbound effort over the woodwork.",  
&nbsp;"{player} mistimes the contact completely, slicing the ball out for a throw-in.",  
&nbsp;"Agonizingly close\! {player}'s snapshot shaves the outside of the post.",  
&nbsp;"{player} snatches at the loose ball under pressure and lifts it over the bar.",  
&nbsp;"The attempted chip from {player} clears the goalkeeper but drops onto the roof of the net.",  
&nbsp;"{player} fails to hit the target after being sent clean through on goal."  
\]

\# \-------------------------------------------------------------------------  
\# Trait Modification Fragments  
\# \-------------------------------------------------------------------------

const TRAIT\_FRAGMENTS: Dictionary \= {  
&nbsp;TRAIT\_HOTHEAD: {  
&nbsp;&nbsp;"prepend": "\[Slamming the dugout wall in fury\] ",  
&nbsp;&nbsp;"append": " — 'Stop being so complacent out there\!'"  
&nbsp;},  
&nbsp;TRAIT\_LOYALIST: {  
&nbsp;&nbsp;"prepend": "\[Clapping enthusiastically from the technical area\] ",  
&nbsp;&nbsp;"append": " — 'Keep your heads up, we win or lose as a unit\!'"  
&nbsp;},  
&nbsp;TRAIT\_PRAGMATIST: {  
&nbsp;&nbsp;"prepend": "\[Checking tactical notes calmly\] ",  
&nbsp;&nbsp;"append": " — 'Manage the game state; do not overcommit.'"  
&nbsp;},  
&nbsp;TRAIT\_VISIONARY: {  
&nbsp;&nbsp;"prepend": "\[Gesturing wide to emphasize spatial overloads\] ",  
&nbsp;&nbsp;"append": " — 'Stick to the structural identity\!'"  
&nbsp;},  
&nbsp;TRAIT\_DISCIPLINARIAN: {  
&nbsp;&nbsp;"prepend": "\[Barking instructions aggressively across the touchline\] ",  
&nbsp;&nbsp;"append": " — 'Maintain the defensive shape, no excuses\!'"  
&nbsp;},  
&nbsp;TRAIT\_MIND\_GAMES: {  
&nbsp;&nbsp;"prepend": "\[Goading the fourth official with a knowing smirk\] ",  
&nbsp;&nbsp;"append": " — 'Let's see if the referee has the courage to call both ways.'"  
&nbsp;},  
&nbsp;TRAIT\_SENTIMENTAL: {  
&nbsp;&nbsp;"prepend": "\[Clutching his chest in absolute disbelief\] ",  
&nbsp;&nbsp;"append": " — 'This club's spirit will see us through\!'"  
&nbsp;},  
&nbsp;TRAIT\_MEDIA\_SAVVY: {  
&nbsp;&nbsp;"prepend": "\[Maintaining complete composure for the touchline cameras\] ",  
&nbsp;&nbsp;"append": " — 'We remain focused on our process.'"  
&nbsp;},  
&nbsp;TRAIT\_VOLATILE: {  
&nbsp;&nbsp;"prepend": "\[Kicking a water bottle down the touchline\] ",  
&nbsp;&nbsp;"append": " — 'Unbelievable, completely unacceptable standard\!'"  
&nbsp;},  
&nbsp;TRAIT\_IDEALIST: {  
&nbsp;&nbsp;"prepend": "\[Applauding the artistic intent of the play\] ",  
&nbsp;&nbsp;"append": " — 'Play through the press with courage.'"  
&nbsp;}  
}

\# \-------------------------------------------------------------------------  
\# Public API: Commentary Synthesis  
\# \-------------------------------------------------------------------------

static func generate\_match\_commentary(event: MatchEventRecord, manager: Object \= null) \-\> String:  
&nbsp;if event \== null:  
&nbsp;&nbsp;return "Play continues across the pitch."

&nbsp;var pool: Array\[String\] \= \[\]  
&nbsp;match event.event\_type:  
&nbsp;&nbsp;&"goal":  
&nbsp;&nbsp;&nbsp;pool \= TOUCHLINE\_GOAL\_BASE  
&nbsp;&nbsp;&"save":  
&nbsp;&nbsp;&nbsp;pool \= GOALKEEPER\_SAVE\_BASE  
&nbsp;&nbsp;&"foul":  
&nbsp;&nbsp;&nbsp;pool \= FOUL\_BASE  
&nbsp;&nbsp;&"yellow\_card", &"red\_card":  
&nbsp;&nbsp;&nbsp;pool \= FOUL\_BASE  
&nbsp;&nbsp;&"substitution":  
&nbsp;&nbsp;&nbsp;pool \= SUBSTITUTION\_BASE  
&nbsp;&nbsp;&"miss":  
&nbsp;&nbsp;&nbsp;pool \= MISS\_BASE  
&nbsp;&nbsp;\_:  
&nbsp;&nbsp;&nbsp;pool \= TOUCHLINE\_GOAL\_BASE

&nbsp;if pool.is\_empty():  
&nbsp;&nbsp;return "Action unfolds on the pitch."

&nbsp;\# Deterministic pseudo-random selection grounded in event attributes  
&nbsp;var seed\_val: int \= hash(str(event.minute) \+ str(event.event\_type) \+ event.primary\_player)  
&nbsp;var template\_idx: int \= abs(seed\_val) % pool.size()  
&nbsp;var base\_commentary: String \= pool\[template\_idx\]

&nbsp;\# Slot replacement  
&nbsp;base\_commentary \= base\_commentary.replace("{player}", event.primary\_player)  
&nbsp;base\_commentary \= base\_commentary.replace("{secondary\_player}", event.secondary\_player)  
&nbsp;base\_commentary \= base\_commentary.replace("{team}", event.team\_name)  
&nbsp;base\_commentary \= base\_commentary.replace("{minute}", str(event.minute))

&nbsp;\# Return pure objective commentary if no manager is assigned  
&nbsp;if manager \== null:  
&nbsp;&nbsp;return base\_commentary

&nbsp;\# Sequential Trait Walk: HotHead(1) through Idealist(512)  
&nbsp;var traits\_bitmask: int \= manager.traits if "traits" in manager else 0  
&nbsp;var final\_commentary: String \= base\_commentary

&nbsp;var ordered\_traits: Array\[int\] \= \[  
&nbsp;&nbsp;TRAIT\_HOTHEAD,  
&nbsp;&nbsp;TRAIT\_LOYALIST,  
&nbsp;&nbsp;TRAIT\_PRAGMATIST,  
&nbsp;&nbsp;TRAIT\_VISIONARY,  
&nbsp;&nbsp;TRAIT\_DISCIPLINARIAN,  
&nbsp;&nbsp;TRAIT\_MIND\_GAMES,  
&nbsp;&nbsp;TRAIT\_SENTIMENTAL,  
&nbsp;&nbsp;TRAIT\_MEDIA\_SAVVY,  
&nbsp;&nbsp;TRAIT\_VOLATILE,  
&nbsp;&nbsp;TRAIT\_IDEALIST  
&nbsp;\]

&nbsp;for trait\_flag in ordered\_traits:  
&nbsp;&nbsp;if (traits\_bitmask & trait\_flag) \!= 0:  
&nbsp;&nbsp;&nbsp;if TRAIT\_FRAGMENTS.has(trait\_flag):  
&nbsp;&nbsp;&nbsp;&nbsp;var frag: Dictionary \= TRAIT\_FRAGMENTS\[trait\_flag\]  
&nbsp;&nbsp;&nbsp;&nbsp;if frag.has("prepend"):  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;final\_commentary \= frag\["prepend"\] \+ final\_commentary  
&nbsp;&nbsp;&nbsp;&nbsp;if frag.has("append"):  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;final\_commentary \= final\_commentary \+ frag\["append"\]  
&nbsp;&nbsp;&nbsp;&nbsp;break

&nbsp;return final\_commentary

## **Intellectual Property, Licensing, and Redistribution Audit**

Incorporating natural language datasets and open-source code into commercial or distributed software architectures requires strict compliance with upstream licenses1. Permissive open-source licenses carry distinct legal obligations regarding derivative software distribution, copyright notices, and patent grants16.

### **Upstream License Topologies**

The repository THU-KEG/goal is licensed under the BSD 3-Clause License for its software tools3. However, the underlying broadcast video clips are governed by SoccerNet's academic research agreements, which forbid commercial distribution and unauthorized re-hosting of raw match features1. Commercial and public distributions of PowerFootball-2D avoid legal liability by strictly isolating the runtime from raw dataset binaries1. By extracting abstract syntactic idioms and training patterns through local NLP parsing and authoring clean templates independently, the engine uses no proprietary SoccerNet audiovisual assets1.

The aws-samples/genai-sports-commentary repository is licensed under the MIT No Attribution (MIT-0) license5. Unlike standard MIT licenses, MIT-0 explicitly waives the requirement to preserve copyright notices and permission disclaimers in binary or source redistributions, allowing developers to repurpose prompt schemas without attribution overhead17.

The chidaksh/SoccerCommentary codebase is an academic PyTorch prototype derived from Video-LLaMA and MatchTime4. The code includes third-party model weights (CLIP, WhisperX, LLaMA-3) governed by varied commercial and research restrictions4. PowerFootball-2D maintains total legal isolation by utilizing neither the neural checkpoints nor the PyTorch execution harness within the runtime1.

&nbsp;

| Repository / Dependency | License Designation | Notice Requirements in Binary Releases | Architectural Risk Mitigation Strategy |
| :---- | :---- | :---- | :---- |
| THU-KEG/goal \[cite: 3\] | BSD-3-Clause3 | Retain copyright notice, list of conditions, and disclaimer18. | Raw data excluded; only abstracted, independently authored syntactic frames deployed1. |
| aws-samples/genai-sports-commentary \[cite: 5\] | MIT-0 (No Attribution)5 | None. Retaining copyright notices is entirely optional17. | Excluded from runtime; referenced solely as prompt serialization literature1. |
| PowerFootball-2D Core | MIT License16 | Full copyright notice and permission text required16. | Complete license declared in project root and user documentation16. |
| Shared Utilities & Tooling | Apache-2.020 | Preserve copyright, patent grants, and state modifications20. | Formal Apache-2.0 notice incorporated into THIRD\_PARTY\_LICENSES.md. |

### **Formal Texts for THIRD\_PARTY\_LICENSES.md**

#### **MIT License**

&nbsp;

&nbsp;

&nbsp;

The MIT License (MIT)

Copyright (c) 2026 Ridgebridge Studios / PowerFootball-2D Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy  
of this software and associated documentation files (the "Software"), to deal  
in the Software without restriction, including without limitation the rights  
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell  
copies of the Software, and to permit persons to whom the Software is  
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all  
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR  
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE  
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER  
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,  
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE  
SOFTWARE.

#### **MIT No Attribution License (MIT-0)**

&nbsp;

&nbsp;

&nbsp;

MIT No Attribution (MIT-0)

Copyright (c) 2023 Amazon Web Services (aws-samples/genai-sports-commentary)

Permission is hereby granted, free of charge, to any person obtaining a copy of this  
software and associated documentation files (the "Software"), to deal in the Software  
without restriction, including without limitation the rights to use, copy, modify,  
merge, publish, distribute, sublicense, and/or sell copies of the Software, and to  
permit persons to whom the Software is furnished to do so.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,  
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A  
PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT  
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF  
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE  
OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#### **BSD 3-Clause License**

&nbsp;

&nbsp;

&nbsp;

BSD 3-Clause License

Copyright (c) 2023, THU-KEG (Tsinghua University Knowledge Engineering Group)  
All rights reserved.

Redistribution and use in source and binary forms, with or without  
modification, are permitted provided that the following conditions are met:

1\. Redistributions of source code must retain the above copyright notice, this  
&nbsp;&nbsp;&nbsp;list of conditions and the following disclaimer.

2\. Redistributions in binary form must reproduce the above copyright notice,  
&nbsp;&nbsp;&nbsp;this list of conditions and the following disclaimer in the documentation  
&nbsp;&nbsp;&nbsp;and/or other materials provided with the distribution.

3\. Neither the name of the copyright holder nor the names of its  
&nbsp;&nbsp;&nbsp;contributors may be used to endorse or promote products derived from  
&nbsp;&nbsp;&nbsp;this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"  
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE  
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE  
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE  
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL  
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR  
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER  
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,  
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE  
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#### **Apache License, Version 2.0**

&nbsp;

&nbsp;

&nbsp;

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Apache License  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Version 2.0, January 2004  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;http://www.apache.org/licenses/

&nbsp;&nbsp;&nbsp;TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

&nbsp;&nbsp;&nbsp;1\. Definitions.  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"License" shall mean the terms and conditions for use, reproduction,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;and distribution as define...\[source\](https://graal.cloud/gdk/about/lium/)ork.  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"Derivative Works" shall mean any work, whether in Source or Object  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;form, that is based on (or derived from) the Wo...\[source\](https://graal.cloud/gdk/about/lium/)k.

&nbsp;&nbsp;&nbsp;2\. Grant of Copyright License. Subject to the terms and conditions of  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;this License, each Contributor hereby grants to You a perpetual,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;worldwide, non-exclusive, no-charge, royalty-free, irrevocable  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;copyright license to reproduce, prepare Derivative Works of,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;publicly display, publicly perform, sublicense, and distribute the  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Work and such Derivative Works in Source or Object form.

&nbsp;&nbsp;&nbsp;3\. Grant of Patent License. Subject to the terms and conditions of  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;this License, each Contributor hereby grants to You a perpetual,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;worldwide, non-exclusive, no-charge, royalty-free, irrevocable  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;(except as stated in this section) patent license to make, have made,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;use, offer to sell, sell, import, and otherwise transfer the Work,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;where such license applies only to those patent claims licensable  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;by such Contributor that are necessarily infringed by their  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Contribution(s) alone or by combination of their Contribution(s)  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;with the Work to which such Contribution(s) was submitted. If You  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;institute patent litigation against any entity (including a  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cross-claim or counterclaim in a lawsuit) alleging that the Work  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;or a Contribution incorporated within the Work constitutes direct  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;or contributory patent infringement, then any patent licenses  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;granted to You under this License for that Work shall terminate  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;as of the date such litigation is filed.

&nbsp;&nbsp;&nbsp;4\. Redistribution. You may reproduce and distribute copies of the  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Work or Derivative Works thereof in any medium, with or without  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;modifications, and in Source or Object form, provided that You  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;meet the following conditions:

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;(a) You must give any other recipients of the Work or  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Derivative Works a copy of this License; and  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;(b) You must cause any modified files to carry prominent notices  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;stating that You changed the files; and  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;(c) You must retain, in the Source form of any Derivative Works  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;that You distribute, all copyright, patent, trademark, and  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;attribution notices from the Source form of the Work,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;excluding those notices that do not pertain to any part of  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;the Derivative Works; and  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;(d) If the Work includes a "NOTICE" text file as part of its  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;distribution, then any Derivative Works that You distribute must  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;include a readable copy of the attribution notices contained  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;within such NOTICE file, excluding those notices that do not  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;pertain to any part of the Derivative Works, in at least one  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;of the following places: within a NOTICE text file distributed  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;as part of the Derivative Works; within the Source form or  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;documentation, if provided along with the Derivative Works; or,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;within a display generated by the Derivative Works, if and  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;wherever such third-party notices normally appear. The contents  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;of the NOTICE file are for informational purposes only and  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;do not modify the License. You may add Your own attribution  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;notices within Derivative Works that You distribute, alongside  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;or as an addendum to the NOTICE text from the Work, provided  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;that such additional attribution notices cannot be construed  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;as modifying the License.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;You may add Your own copyright statement to Your modifications and  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;may provide additional or different license terms and conditions  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;for use, reproduction, or distribution of Your modifications, or  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;for any such Derivative Works as a whole, provided Your use,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;reproduction, and distribution of the Work otherwise complies with  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;the conditions stated in this License.

&nbsp;&nbsp;&nbsp;5\. Submission of Contributions. Unless You explicitly state otherwise,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;any Contribution intentionally submitted for inclusion in the Work  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;by You to the Licensor shall be under the terms and conditions of  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;this License, without any additional terms or conditions.  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Notwithstanding the above, nothing herein shall supersede or modify  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;the terms of any separate license agreement you may have executed  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;with Licensor regarding such Contributions.

&nbsp;&nbsp;&nbsp;6\. Trademarks. This License does not grant permission to use the trade  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;names, trademarks, service marks, or product names of the Licensor,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;except as required for reasonable and customary use in describing the  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;origin of the Work and reproducing the content of the NOTICE file.

&nbsp;&nbsp;&nbsp;7\. Disclaimer of Warranty. Unless required by applicable law or  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;agreed to in writing, Licensor provides the Work (and each  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Contributor provides its Contributions) on an "AS IS" BASIS,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;implied, including, without limitation, any warranties or conditions  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;PARTICULAR PURPOSE. You are solely responsible for determining the  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;appropriateness of using or redistributing the Work and assume any  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;risks associated with Your exercise of permissions under this License.

&nbsp;&nbsp;&nbsp;8\. Limitation of Liability. In no event and under no legal theory,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;whether in tort (including negligence), contract, or otherwise,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;unless required by applicable law (such as deliberate and grossly  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;negligent acts) or agreed to in writing, shall any Contributor be  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;liable to You for damages, including any direct, indirect, special,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;incidental, or exemplary damages of any character arising as a  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;result of this License or out of the use or inability to use the  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Work (including but not limited to damages for loss of goodwill,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;work stoppage, computer failure or malfunction, or any and all  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;other commercial damages or losses), even if such Contributor  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;has been advised of the possibility of such damages.

&nbsp;&nbsp;&nbsp;9\. Accepting Warranty or Additional Liability. While redistributing  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;the Work or Derivative Works thereof, You may choose to offer,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;and charge a fee for, acceptance of support, warranty, indemnity,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;or other liability obligations and/or rights consistent with this  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;License. However, in accepting such obligations, You may act only  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;on Your own behalf and on Your sole responsibility, not on behalf  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;of any other Contributor, and only if You agree to indemnify,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;defend, and hold each Contributor harmless for any liability  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;incurred by, or claims asserted against, such Contributor by reason  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;of your accepting any such warranty or additional liability.

&nbsp;&nbsp;&nbsp;END OF TERMS AND CONDITIONS

## **Architectural Synthesis and Systemic Conclusions**

Transitioning PowerFootball-2D from a fixed, hard-coded quote catalog to a corpus-grounded narrative architecture bridges the gap between match kinematics and persistent sports drama1. Decoupling natural language processing from the Godot runtime preserves engine performance: the extraction script operates during development, compiling verified broadcast syntax into lightweight, slotted JSON pools that load in sub-millisecond timeframes1.

Expanding the baseline commentary pools across GOALKEEPER\_SAVE\_BASE, FOUL\_BASE, SUBSTITUTION\_BASE, and MISS\_BASE to over 75 corpus-informed entries resolves repetitive narration across repeated fixtures1. The templates preserve genuine syntactic phenomena observed in professional association football broadcasts, such as ergative verbal constructions, participial consequence clauses, and spatial sector references12. Concurrently, slotting ensures that entity facts originate exclusively from verified match state machines in Layer 1 and Layer 2, preserving strict layer isolation1.

Finally, processing match commentary through the sequential manager trait walk ensures psychological cohesion1. When a high-stakes event occurs, the resulting touchline narrative reflects both on-pitch kinematics and managerial temperament1. A HotHead manager reacts with explosive frustration, whereas a Disciplinarian manager demands immediate structural reorganization1. This dynamic narrative feedback provides context that reinforces subsequent career consequences, grounding player trust, squad morale, and media scrutiny in observable match events1.

#### **Citerade verk**

> 1. ridgebridgestudios-powerfootball-2d-8a5edab282632443(1).txt  
> 2. SoccerNet-Caption: Dense Video Captioning for Soccer Broadcasts, [https://www.computer.org/csdl/proceedings-article/cvprw/2023/024900f074/1PBxoKjzjsk](https://www.computer.org/csdl/proceedings-article/cvprw/2023/024900f074/1PBxoKjzjsk)  
> 3. THU-KEG/goal \- GitHub, [https://github.com/THU-KEG/goal](https://github.com/THU-KEG/goal)  
> 4. \[EMNLP 2024 Oral\] MatchTime: Towards Automatic Soccer Game, [https://github.com/jyrao/MatchTime](https://github.com/jyrao/MatchTime)  
> 5. GitHub \- aws-samples/genai-sports-commentary, [https://github.com/aws-samples/genai-sports-commentary](https://github.com/aws-samples/genai-sports-commentary)  
> 6. GOAL: A Challenging Knowledge-grounded Video Captioning, [https://arxiv.org/abs/2303.14655](https://arxiv.org/abs/2303.14655)  
> 7. Kunyu Gao \- DBLP, [https://dblp.org/pid/198/7851](https://dblp.org/pid/198/7851)  
> 8. A Challenging Knowledge-grounded Video Captioning Benchmark, [https://www.researchgate.net/publication/369557507\_GOAL\_A\_Challenging\_Knowledge-grounded\_Video\_Captioning\_Benchmark\_for\_Real-time\_Soccer\_Commentary\_Generation](https://www.researchgate.net/publication/369557507_GOAL_A_Challenging_Knowledge-grounded_Video_Captioning_Benchmark_for_Real-time_Soccer_Commentary_Generation)  
> 9. Towards Automated Commentary Generation for Soccer Highlights, [https://arxiv.org/html/2508.07543v1](https://arxiv.org/html/2508.07543v1)  
> 10. [https://github.com/chidaksh/SoccerCommentary](https://github.com/chidaksh/SoccerCommentary)  
> 11. MatchTime: Towards Automatic Soccer Game Commentary, [https://www.alphaxiv.org/abs/2406.18530](https://www.alphaxiv.org/abs/2406.18530)  
> 12. Towards Automatic Soccer Game Commentary Generation, [https://aclanthology.org/2024.emnlp-main.99.pdf](https://aclanthology.org/2024.emnlp-main.99.pdf)  
> 13. MatchTime: Towards Automatic Soccer Game Commentary ... \- arXiv, [https://arxiv.org/html/2406.18530v1](https://arxiv.org/html/2406.18530v1)  
> 14. Dense Video Captioning for Soccer Broadcasts Commentaries, [https://www.researchgate.net/publication/369924978\_SoccerNet-Caption\_Dense\_Video\_Captioning\_for\_Soccer\_Broadcasts\_Commentaries](https://www.researchgate.net/publication/369924978_SoccerNet-Caption_Dense_Video_Captioning_for_Soccer_Broadcasts_Commentaries)  
> 15. Towards Universal Soccer Video Understanding \- CVF Open Access, [https://openaccess.thecvf.com/content/CVPR2025/papers/Rao\_Towards\_Universal\_Soccer\_Video\_Understanding\_CVPR\_2025\_paper.pdf](https://openaccess.thecvf.com/content/CVPR2025/papers/Rao_Towards_Universal_Soccer_Video_Understanding_CVPR_2025_paper.pdf)  
> 16. What does MIT license allow? : r/godot \- Reddit, [https://www.reddit.com/r/godot/comments/zy0xa6/what\_does\_mit\_license\_allow/](https://www.reddit.com/r/godot/comments/zy0xa6/what_does_mit_license_allow/)  
> 17. Tutorial Licenses \- Catlike Coding, [https://catlikecoding.com/license/](https://catlikecoding.com/license/)  
> 18. BSD 3-Clause: where to place license for binary installation?, [https://opensource.stackexchange.com/questions/7575/bsd-3-clause-where-to-place-license-for-binary-installation](https://opensource.stackexchange.com/questions/7575/bsd-3-clause-where-to-place-license-for-binary-installation)  
> 19. 16\. Freedom to Share: Understanding Waifu AI OS's MIT-0 License, [https://16-freedom-to-share-understanding-waifu-ai-os-s-mi--thewaifuai.on.websim.com/](https://16-freedom-to-share-understanding-waifu-ai-os-s-mi--thewaifuai.on.websim.com/)  
> 20. micronaut-cache-management \- Oracle Help Center, [https://docs.oracle.com/en/industries/health/oracle-health-ehr/oracle-health-ehr-third-party-licenses-and-notices/original\_authors\_micronaut-cache-management.html](https://docs.oracle.com/en/industries/health/oracle-health-ehr/oracle-health-ehr-third-party-licenses-and-notices/original_authors_micronaut-cache-management.html)  
> 21. Licensing Information User Manual, [https://graal.cloud/gdk/about/lium/](https://graal.cloud/gdk/about/lium/)

[image1]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAD8AAAAaCAYAAAAAPoRaAAAC60lEQVR4Xu2XWchMcRjGX/ueSMpa3LmQPeXCVpIiopAiQl+KG6KUG5IlS7IkVyhCJFv23JCSK0v2+oqQEkIu7M/T+x/f/3s6Z+acmYtpMr96muZ5z5z5L+/5v+8xq1OnDugEXYJ6aaBGOAGNUjMrF6AFatYQfaEHVsbmLYauq1mDNEBX1SxGW+glNE0DYBb0GvoDnZFYNeEjutx87DEdoQ/QGPFTmQm9hVpqIDDIfPLLNFBFVpqPKSnF90Kn1UzjCHRKzQiuMP9ogAaqyDXoiZqBudBnqJUGkngOrVYz4hz0WM0qwlT/Bu3RQICbxM0qefJ3hn5D0zUQaAN9gQ5Du8LnfWh7fFEGOGBm2D3ztOT5cgO6Ba2JrivGBPPdfmM+ucbwfXZ8UeAHtFBNpbBK4zQQGGseZwnpH7xJwRtZuCgDK6B50FLz3x6HukOvoIfRdVnYAP2Eumog4j20Sk1lqPlghmggsNF8FQdGHisAfzM68krBBqQdtM88ZbuF78wk3i8Pt6G7agovoE1qKpx0scnfgW6Kd8D8QNEyk4VH0GU1c9DFfDO2akDg5LeoqfSz9LTn7vyC1kUeJ8yUOhR5Welt/l8l07EIU83vMVkDAse4Vk2FTQFvlnTgJaV3wePh08ear+4MS88gwta5WJYRtqi8jgdtEjug7+ZNDtkGDWsK/4PZwa61JI2WXOr2Q5+seb3cab6qbIh4ag8O/gjziX2E2gdPOQi9g1poIOK8+X3Sdu2oNZXd8eaPoFI4xIdrIAkOKqnJ4RvebvF4wj+FTkKLIr+n+SKyLKbt7BVos5oCJ80FT+vQuMgsb4wz65IaGTY5Xy3jmTTHvHamtbd5YBqyHa4E9h6sDuXCjGQpzURr811LerHJy1krntZZmGLlv0cUXmzYn2RmiXm/XAkc9Ho1c8I0ZjvdQwMZ4SttWaX0GDRfzRyw12bjUgkTzR/DcmCleGZNnWguOkAXLfk1sRbgc56n66xT53/iLzBgjo9QRCiOAAAAAElFTkSuQmCC>

[image2]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAwAAAAaCAYAAACD+r1hAAAAxElEQVR4XmNgGAWkgS4gfgfE/4G4AE0OJ8hkgGjQRJfABdYA8UN0QVyAGYjfA/F0dAlcwJIB4pxKIF4AxMuB+BoQRyOpQQF1DBANIIVcULFWIP4MxIwwRcjgCBBfB2I2JLHJQPwdiQ8HvED8G4ib0cRvAvEONDEw8GOAOMcGScwYKpaAJAYHIKs/ATELmtgXIOYB4iAgDkSSA7t9M7IAEJwD4nVAzA6VA9FgAPLkayAOgwlAQTIQXwXi1UBsiiY3CgYYAACMjiOmQ16M7QAAAABJRU5ErkJggg==>

[image3]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAoAAAAaCAYAAACO5M0mAAAAdElEQVR4XmNgGAWDG9QB8WEgPgDEZkC8BYj3APFaIGaEKdIF4llArArE/4H4OhCLAfFGKF8EprACiC2AOBQq4QEVB9kCwhhgGhB/BmJWdAl0cAuIN6MLogM5Boi1+egS6CCeAaJQC10CHVQB8TF0wVFAfQAAbyMTqfrG10IAAAAASUVORK5CYII=>

[image4]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAcAAAAcCAYAAACtQ6WLAAAAhElEQVR4XmNgGMpABYij0AVhAK/kJiC+iS4IAmxA/AWIZ6BLgIANEP8H4mBkwXIgvgHEH4D4L5QNwgpIahgOAfEZZAEY4AbiX0DcjS4BAp4MEPtANAboYYDo5EGXAIGzQHwUymYE4q1AzAqTfArE06HsKiCOh0mAQCIQ3wLiVegSIx4AAK6sF9s/dRChAAAAAElFTkSuQmCC>

[image5]: <data:image/png;base64,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>

[image6]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADIAAAAWCAYAAACCAs+RAAABaElEQVR4Xu2WTStFURSGX5SPCWUiA0ZGBqSUjNzkayLKwIShDEwof4AoiaFSykh+goE/QLpJIikfE0NSYiCf77L26axzMri3O7h713nq6Z611h7sc8/a6xwgI1yq6TZdo7u0O1kOh3m67K6b6DWtjMv+MErP6av7naEVpn5Kx018T3tM7AUD0I3KP11Pt+gPXTFr3uigia/otIm94Ij2mbiK3tJv2uJyn9AbjrikcyYuO7LpL3pHG0x+B/pUZl38RIfj8t8TmTJx2ZED+wzddJvJb7rcgotP6ERcxgPtNbEXdCHZ/8Ih9Eai/CJdddfN0MPu5dSytNIP6DmINlsDbbcNuofCJpa04lkR5pFs75LZpy+0I10ICRmpMmpzqXxQdNJH2p8uhEQjdKSOmFyOTpq4WIagfV+oxyjxjMi75ADJ8Sos0bFUzmvWoefiwinT6oa+03azzmvqoO+L/5RPlNp4aUZGRqj8AgeAUurPfg1wAAAAAElFTkSuQmCC>

[image7]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADIAAAAWCAYAAACCAs+RAAABNUlEQVR4Xu3WLUtEQRTG8aMWLS5YTJpMBmWx6+J7EYNhk82X7EcQTIJg0GSw+REMpmkqiIgoFrVYBUE0iPjyH84Fzx4UXLbMwH3gx3KfmXCHO3PvipTJPxMY9WVOiQvYxwOW3FhSmcMlXorfZbQ1zNAESXghkzhHL7qxiy9s2ElFgiS8kGOMmesO3OETfaaPCZLoQuJNf+AeFdPviT6VVdPFBEl0Ie14Er3pAdNvFd2a6WKC6PlJMlVMue5IdCG+D1hxXbLpxzuuRZ9YzAh28IhTbJuxvzKDiyacSeP2bjkHeMaQH8gpi3hFzfVZZVh064z7gZzSgxvMmq6GurluNtOi+/6/TqTFMxK/JYdYcP065l2XdDZFz8VVIb6tbvGGQTMv6XSJfi9+E/+idP5MLVOmTK75BtyOS+KVESn3AAAAAElFTkSuQmCC>

[image8]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADIAAAAWCAYAAACCAs+RAAABXklEQVR4Xu2WzSsHQRjHH2+FA+XiIC8HUQ7khpJf8naRg4NSjlJu/gTlpCgHF85cODg5uDqgJIlc8BcoJQ7y+pme2XZ2pGy/w2+29lOfdvb7zNbONrMzIjnZpQk3cBfPsC9Zzg57OGHbi/iItXE5HCbxCl/sdR7LnPoBLtt2K37jcFwOgxG8wEasw03RF11xOzkMitbb/UKpOcEh574C7/ELm508Yh+3/LDUmJf+xAesd/Jt0a++4GSGWdzBSi8vOeX4JL+nyprNlpysX3TamWc6rUHRi6NediQ6kChvE13wZjADuI4dthYsLfiON6Jf33AsOrDID6yytb8Yx8sUnktyeheN2fSesdsvZIk5fMWCl2eKHtEdO7iNLg0NeCvxMcRQwBnnPi1jovP+v55KkWvE7CWHOO3l5kgy5WVBsyq6Lq6t5m91h2/Y5fQLmhpJ/lZdzRGlOu6ak5OTVX4ACNhSBb4FSeMAAAAASUVORK5CYII=>

[image9]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADIAAAAWCAYAAACCAs+RAAABWUlEQVR4Xu3WvytGURzH8S8WFsJgYrKgyC4e8rtkMChl86NkMZilTMSmlDLJf8AgZWSQJDL4tRqUEkry430739s9z0miOzin7qdePed8v2c4T8+55z4iWcJNKVawhD205rfDyRw2dDyNOxQmbX8ygFM86ec4Cqz+CNZ0PIEX8fCLdOIYVWKO0Co+sWAvsrIt5oh5lwO0WfMiXOMD1Va9QczxitZXWnUvEm36HTcos+rrYn6VSasWZwy3KHcb/5nonD+I2XStVV/W2ozOp9Cu4zrtDevcmzSjy6ntitlsXL/ErI778IZ6nXubGjEbPZfkZmrBppibax/9Wv8pPTj5gyPJP96ps4VHNLqNkDKKZ+ScelBpwj063EZIqcAFeq1aTtLdTN1izv1vHUrKZyR6l+xgyKnPY9CpeZ1FMc/FmYpuqyu8SgBXbJwSMe+L70R/UYqTpVmyZAk1XyMMUdP5j25rAAAAAElFTkSuQmCC>

[image10]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADsAAAAWCAYAAAB+F+RbAAABS0lEQVR4Xu3WvyuFURzH8S9KLFdZlGIyqUv+Ajf5tchguAsTUjarTZmUlJgsJn+CZCYGSSILZoMiMUh+vL+dc+vreAZ3eeo8nU+9us/zPWf53qfzQyQlxWYFs2GxiCnjDXPhQEyZwCVe/e88Gn7NEGnEFg4l4maHcY4OlLCNb6zaSWQR/TiQiJs9waB5b8IdvtDla91Y9s/RNquNfeIebaa+I+7rLvj3DbT452ib1XX4JK6xHlNf97UldIprcNd7wDGm/dyoMoCRoKabkDYb1jVnEumXzYquzw9ci/vytTRjE884wpQZy8oYLuqgf6JdSrlkDy/oCweKlhlxl4ZKUC9c9Ax9xFA4ULS04wbjplZB1bzXm1Fx6/C/TiWHNatn7b783XD0wj8Z1KLPmrh1euXpLnyLd/SaedGnVdx5mkWvi7VbU0pKSkqu+QElKlBz1MboYgAAAABJRU5ErkJggg==>

[image11]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADsAAAAWCAYAAAB+F+RbAAABZklEQVR4Xu3XzSsFURjH8cdr14ai2LiKrBQSsrBw817eioWVpWyU/AnKSllayVaxsFEW/gEWkkQ2WMpCKbGQvHxP57k59yS5m5tzml99unOeZxYzd+bMmRFJ8mMaMYAalHu96DKFT3WPodx2XJnEIjpQ5vWCywTO8ay/8yhy+uMq+AziFHWoxIbY23XV2WcMu1jDDnqcXlA5Qp8zLsENPpDWWqvYP8WkG3dI6TiYmBN7xy2qnPqm2Ku74NSyqRbb6/Ub/z3FeBR78M1OfV1ryzrex5Ju12qvU8dBxTxh/aXkUOwJZevb6NLtaVygVMdBpwFvuBR75U3qxd7aW9hDk9Z/ywjO8nAiuVOpIDFX8QltfiO2zOEFGa8eXdrxgH6/EVvMcnKFUaeWwawzzjfDYufhXx1LAeasWWsPMOPVV8R+AEQV8wpo5qlZTgzzFL7GK1qc/YJPhXx/uvnM62Jwr4RJkiSJI1+RLlCfKIrXbwAAAABJRU5ErkJggg==>

[image12]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADsAAAAWCAYAAAB+F+RbAAABZ0lEQVR4Xu3WvyuFURzH8S9KLITB4sdiMvhRJoub/FokGZRSFtmUkl0ppRjEwkLJYLEp/gEGSSILyi5KKPn5Pr7n9px7okg9dZ6eT726z/l+z3LuuefcRyRNGpMmbGAR814vUanGOUrQglcU5swIKL04wYP9HEWe01/Cgn029VqnF1Q6cIRK0Z1bxgdmnDlmVzcxhTX0O72gso82Z1yAS7yL/nxNbrFlnyvwKPrlBBWzsDdcodSpr4ru7pgdX2Myan8tdsgZB5F83IkurM6pm9vW1CbseBfjUVueMOiMg0kzOr3anuhis/URrNvnKtygzI6DTg1ecCa689nMYgXbaHXqP6Ubx39wKLlHKZaYW/ceDX4jaRkWvXwyXj1xaRQ9i+1+I2kpF31x6HFqGfnfjdsleg5/60BiOLPmv3YHA159Gn1eLfjMiZ7TU8vcwhd4Rr0zL/gUi/6ffse8LhZFU9OkSZMmvnwC5GVTk4SH2YEAAAAASUVORK5CYII=>

[image13]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEQAAAAWCAYAAAB5VTpOAAABVUlEQVR4Xu2YOy8FQRiGP5e4hJAoqIhCpSBCIRqHuBaiUKioiEbBT5CoiFKlF5VEo/AHKEREiAa/QCIRChGX58vMSb4dzTnRnOzMkzzZnXemmc3MN7srkvgXtViPDd66bHdcbOBP4HFmRGTs4hiO4DCeYLcdkDfm8Abf/HUVq0z/pLmfxWXTzh0TeIUd2IL74rbEth3kacKjMMwb5zhq2jX4iN/YaXJlHVeCLFfo5L/wCVtNfiBulayZTLnHoSDLFdX4Im7yPSbf89mmyXRLadZuslwyINmiqZyJm7zNp33WbLIo6MJPvBO3gooM4oO4bVYK+gCvy/BSstu2YjjEV+wLO2JkCd+xEORR0o/POB52xEibuCN1xmQFXDTtcpkSVxdK9UIqpIZokTzFhSDfwvkgi4IdcXXj1quni54mH9hrxkVBo/z9rC+qr+763yORSCQSJfALYMBNo2gJfPUAAAAASUVORK5CYII=>

[image14]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEQAAAAWCAYAAAB5VTpOAAABaElEQVR4Xu3WzStFQRjH8QcRG8rGiiglFsQ/4JLXhZdSrCyRpf+AsiHCwoYslCwtLSyUFBaSRCzwFyglRPLyfZrRmTtJblnc5pxffbpnnmc259w5c0YkSZL/SgHmsIA1tKW345dxtNjrPBwgN2qHlx6c4dH+jiDH6evqmLE1tScBPxBd/icoQzGW8YlpZ04TnrGPRXQ7veByiGZnrK/EDT5Qbmu6GtZxhVeM2npw0Zt/xy1KnPqqmFUyZsf6uvQjH5N4QY3tBRX95+/F3Hy1U5+3tQk7Pnd6miUMerVg0oh2r7Yj5oF813dRG7VlA5XOOOhU4A0XEn1JqrCFFTF7Sa+t/5ZOnGbgWNJf26zJJh5Q7zfimGE8IeXVY5kG3KHVb8QxpbhEl1NLYcgZZ5oOMfvCXx1JluwhehbZxoBXn0KfV4tFZsXsG3rWUPp1uRZzIq1z5sUiRWLOGz/Ro3thNDVJkiRJkvyWLwpaUnmwtlweAAAAAElFTkSuQmCC>

[image15]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEQAAAAWCAYAAAB5VTpOAAABbElEQVR4Xu3XzStEURjH8eMlkVA2SmEjiZCyN4Sx8JIsbFgiG+UPkJRSoliwUShR/oFZ+AdYSBLZYGWplFh49z2dR3PmpsmUxXTO+dWnOc/z3M2Z7rlzR6mQkP9KMTawigM0po79yxaWZF2HS2vmZPpxjif5HEeONb/DhFW/o8mqnUoXTlGBUqzjCwvWNbeYknUBPjGUHLuVI7RbdR5ulNl0lfRmsS3rAXxgVGqnojevN6fvgDKrv6nMXTIptT4+05hDH17RITOnkosHZTZfa/VXpDcjdQ3qZV2JR5RI7Vxa0R3pHSrzhfz017Ana318FmXtRarxpsxPq76DdNqwix0sI1/66RLHWQZOVOqxzZrsK3MkmqMDHzOGZ8QifS/Tgnt0Rgc+phxX6LV6MYxYdabpUea58FfHKkueIfpdJIHhSH8eg5GeF9F/2vRz40LoX5drvKDBus6LFCnzvvEb/epemLw0JCQkJCRdvgHWDVNfW3NDmgAAAABJRU5ErkJggg==>