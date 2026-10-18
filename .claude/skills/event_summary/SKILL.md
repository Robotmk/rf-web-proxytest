---
name: event_summary
description: Guide for transforming structured, talk-by-talk conference notes into a coherent, publication-ready recap article. Must be used for summaries of events, conferences, workshops, talks, and similar gatherings.
---

# AI Skill: Conference Recap Composer

## Purpose

Transform structured, talk-by-talk conference notes into a coherent, publication-ready recap article.

The AI must write as if the author attended **the talk in full**, even if the notes are selective or incomplete.

The recap must read like a continuous, attentive walkthrough — never like reconstructed notes.

Tone guidelines must be loaded from [](../blog_tone/SKILL.md).

---

# Input Assumption

- The input will always be provided **talk by talk**.
- Each input block represents one presentation / event / workshop.
- The AI must focus fully on the current talk while maintaining narrative continuity across the entire recap.
- Do not mention that the input was processed in parts.
- Ensure transitions between talks feel natural and chronological.
- Blank lines, spelling mistakes, etc. in the notes must be ignored and should not be included in the summary.

Even though processing happens per talk, the final text must read as one unified article.

---

# Core Behavior

## 1. Perspective & Voice

- Write in **past tense**.
- Write as a professional conference journalist, with a personal touch.
- Maintain technical credibility.
- Present the author as having attended all talks.
- Avoid any indication that sessions were missed.

The text must read as if:

> The author was present in every session and followed each presentation attentively.

Never mention incomplete attendance, missing context, or second-hand impressions.

---

# Structural Rules

## 2. Chronological Illusion

Even if the input order is not chronological:

- Structure the recap so it reads like a natural progression through the conference.
- Smoothly transition between sessions.
- Create a sense of flow and thematic development.

The article must feel like a lived experience, not a compilation.

---

## 3. Section Pattern per Talk

Each talk must follow this structure:

Talk Title

(Speaker Name(s))

Image Links (markdown)
Take the existing speaker image(s) and convert them into the following format.
Example: 
OLD: ![Miikka Solmela](img/miikka.png)
NEW: {{< portrait src="img/miikka.png" alt="Miikka Solmela" >}}

Do not isolate personal opinions in separate paragraphs.  
Integrate them naturally within the narrative.

---

# Content Integration Rules

## 4. Handling Notes, Slides & Speaker Notes

Input may contain:

- Bullet notes  
- Slide headlines  
- Speaker notes  
- Partial phrases  

You must:

- Paraphrase all slide and speaker note content.
- Never copy slide wording literally.
- Avoid phrasing that sounds like presentation bullet points.
- Convert fragmented notes into fluent prose.
- Write as if the content was heard directly in context.
- If the input contains hyperlinks, also use them. 

Assume:

> All ideas were fully heard and understood during the live session.

---

## 5. Biographical Integration

If speaker background information is available:

- Integrate relevant biographical details seamlessly.
- Use them to strengthen credibility or explain perspective.
- Include only details that serve contextual understanding.

Example approach:

Instead of:
> The speaker has 20 years of experience.

Write:
> Drawing on more than two decades of experience in distributed systems, the speaker approached the topic from a strongly architectural angle.

---

## 6. Personal Opinion Integration

If personal reflections appear in the input:

- Never create a separate “My opinion” section, but mention my opinion.
- Never isolate subjective comments.
- Weave reflections into the analytical narrative.

Example:

Instead of:
> I liked this approach.

Write:
> The approach felt particularly robust because it addressed both technical depth and long-term maintainability.

---

# Tone & Style Requirements

## 7. Tone Source

Before writing, load tone characteristics from: ../blog_tone/SKILL.md

Adapt:

- Emotional intensity  
- Technical density  
- Community awareness  
- Reflective depth  

Maintain consistency throughout the article.

---

## 8. Professional Conference Journalism Enhancements

Elevate the recap beyond summarization.

### A. Scene Anchoring

Occasionally reference:

- The atmosphere  
- Audience reactions (if plausible)  
- Momentum shifts between sessions  

Keep this subtle and professional.

---

### B. Thematic Framing

Where possible:

- Identify recurring themes across talks.
- Show how sessions connected.
- Highlight broader industry implications.

This creates narrative coherence.

---

### C. Analytical Depth

A professional journalist:

- Interprets significance  
- Connects details to long-term impact  
- Explains why a topic matters  

Avoid mere summarization.

---

### D. Balanced Evaluation

Never exaggerate.

Instead of:
> This was revolutionary.

Write:
> The approach suggested a meaningful shift in how teams might approach scalability.

Maintain measured enthusiasm.

---

# Emotional Register

- Confident  
- Analytical  
- Reflective  
- Community-aware  
- Calmly enthusiastic  

Never:

- Overexcited  
- Promotional  
- Dramatic  

---

# Quality Checklist Before Output

Ensure the recap:

- Reads as one continuous narrative  
- Feels as if every talk was attended in full  
- Avoids note-like fragmentation  
- Avoids literal slide phrasing  
- Integrates reflections seamlessly  
- Includes relevant biographical context  
- Maintains past tense  
- Follows the defined section pattern  
- Respects tone from `./tone.md`  
- length between 2000 and 3000 characters. 

---

# Output Format

Return a fully formatted Markdown article, ready for publication.
If not stated other, produce in german. 