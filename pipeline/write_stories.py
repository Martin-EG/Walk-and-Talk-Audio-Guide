"""Step 4: Gemma (local, via Ollama) writes one short spoken story per stop, from the given facts only.

Stops with a Wikipedia extract get the full prompt (including "one surprising fact"). Stops with only
OSM tags get a "thin facts" prompt: shorter (THIN_MIN_WORDS-THIN_MAX_WORDS) and no surprising fact,
because a model asked to fill length or find a surprise with nothing to go on will make it up.
Thin stops use config.THIN_STORY_MODEL (bigger) and get no nearby-area facts.
Checks each story: word count in range, no number that isn't in the facts, and (thin stops)
no "did you know"-style phrases. On any problem Gemma gets one retry with it spelled out.
Capitalized words that don't appear in the facts are flagged (not rejected) in review.md
so you can check them by hand.

Optional hand-written facts: pipeline/notes/<route>.json, keyed by OSM id:
  {"way/1373216639": {"facts": "Opened as a cinema in 1934 ...", "source": "https://..."}}
A stop with notes is treated like a stop with Wikipedia text.

Reads stops_ranked.json and area.json, writes stories.json and review.md.

Standalone:  python pipeline/write_stories.py --route mexicali --lang en
"""

import argparse
import json
import re
import unicodedata

import requests

import cache
import config
from geo import distance_m

LANGUAGE_NAMES = {"en": "English", "es": "Spanish"}
SKIP_TAGS = {"name", "building", "access", "drive_through", "wikidata", "wikipedia", "healthcare",
             "addr:housenumber", "addr:postcode", "addr:state", "addr:country", "check_date"}
EXTRACT_CHARS = 1500
AREA_CHARS = 600
AREA_MAX_M = 250  # area articles geotagged this close to a stop are given as nearby context

SYSTEM_PROMPT = """You write short spoken stories for an audio walking tour. The listener is standing at the place, phone in pocket, listening through earbuds.

Rules:
- Write in {language}, even if the facts are in another language. Keep proper names as given.
- {min_words} to {max_words} words; aim for about {target_words}. Second person ("you"), present tense.
- Open with something the listener can see from where they stand, framed as an invitation to look (e.g. "Look up at...", "In front of you...").
- Use ONLY the facts provided. Never add dates, numbers, names, people, events, history, purposes, or descriptions of colors, materials, shapes, or details that are not in the facts. Do not use your own background knowledge.
{mode_rules}
- Plain text only: no title, no headings, no lists, no quotation marks around the story, no stage directions."""

RICH_RULES = "- Include one surprising fact, taken from the facts."
THIN_RULES = """- The facts about this place are thin: there is NO surprising fact about it, so do not include one. Never write "did you know", "surprisingly", "interestingly", or "originally".
- Keep it short. Say plainly what kind of place it is, invite the listener to take a look, and stop. A short honest story is better than a long one.
- Do not translate or explain the place's name. Never mention OpenStreetMap, tags, or "the facts".
- Do not describe sounds, crowds, weather, figures, materials, colors, shapes, the street, the neighborhood, or what the area is known for; you cannot see the place. Never say what kind of area it is (residential, industrial, commercial) or what it is near."""
# In a thin story these phrases almost always introduce an invented fact.
THIN_BANNED = ["did you know", "surprising", "interesting", "originally", "was built", "was created",
               "built in", "dates back", "history of", "known for", "area is", "residential",
               "industrial", "commercial", "located near", "is near"]


def facts_text(stop, area, note):
    """The only material Gemma may use. Also returns the source URLs behind it."""
    lines = [f"Name: {stop['name']}"]
    sources = [f"https://www.openstreetmap.org/{stop['id']}"]
    tags = {k: v for k, v in stop["tags"].items() if k not in SKIP_TAGS and not k.startswith("name:")}
    if tags:
        lines.append("OpenStreetMap tags: " + "; ".join(f"{k}={v}" for k, v in tags.items()))
    if stop.get("wikidata_description"):
        lines.append(f"Short description: {stop['wikidata_description']}")
    if stop.get("wiki"):
        lines.append(f"Wikipedia ({stop['wiki']['lang']}): {stop['wiki']['extract'][:EXTRACT_CHARS]}")
        sources.append(stop["wiki"]["url"])
    if note:
        lines.append(f"Notes: {note['facts']}")
        sources.append(note["source"])
    for article in area:
        if distance_m(stop["lat"], stop["lon"], article["lat"], article["lon"]) <= AREA_MAX_M:
            lines.append(f"Nearby area, NOT this place ({article['title']}, Wikipedia {article['lang']}): "
                         f"{article['extract'][:AREA_CHARS]}")
            sources.append(article["url"])
    return "\n".join(lines), sources


def plain(text):
    return unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()


def word_count(text):
    return len(text.split())


ROMAN = {"XV": 15, "XVI": 16, "XVII": 17, "XVIII": 18, "XIX": 19, "XX": 20, "XXI": 21}


def invented_numbers(story, facts):
    fact_numbers = set(re.findall(r"\d+", facts.replace(",", "").replace(".", " ")))
    # "siglo XX" in a Spanish extract legitimately becomes "20th century" in English.
    fact_numbers |= {str(n) for r, n in ROMAN.items() if re.search(rf"\b{r}\b", facts)}
    return sorted({n for n in re.findall(r"\d+", story.replace(",", "")) if n not in fact_numbers})


def unknown_names(story, facts):
    """Capitalized words mid-sentence that never appear in the facts: possible invented names."""
    fact_words = set(re.findall(r"[a-z0-9]+", plain(facts)))
    flagged = []
    for sentence in re.split(r"(?<=[.!?])\s+", story):
        for word in re.findall(r"\w+", sentence)[1:]:
            if word[0].isupper() and plain(word) not in fact_words and word not in flagged:
                flagged.append(word)
    return flagged


def chat(messages, model):
    payload = {
        "model": model,
        "messages": messages,
        "stream": False,
        "options": {"temperature": config.LLM_TEMPERATURE, "seed": 42, "num_predict": 400},
    }
    cached = cache.get_json("llm", payload)
    if cached is not None:
        return cached["content"]
    resp = requests.post(f"{config.OLLAMA_URL}/api/chat", json=payload, timeout=600)
    resp.raise_for_status()
    content = resp.json()["message"]["content"].strip().strip('"').strip()
    cache.put_json("llm", payload, {"content": content})
    return content


def word_range(thin):
    if thin:
        return config.THIN_MIN_WORDS, config.THIN_MAX_WORDS
    return config.STORY_MIN_WORDS, config.STORY_MAX_WORDS


def problems(story, facts, thin):
    found = []
    words = word_count(story)
    min_words, max_words = word_range(thin)
    target = (min_words + max_words) // 2
    if words > max_words:
        found.append(f"It is {words} words, too long. Rewrite it in at most {target // 16} sentences "
                     f"(about {target} words); keep the opening{'' if thin else ' and the surprising fact'}, drop the rest.")
    elif words < min_words:
        found.append(f"It is {words} words, too short. Keep every sentence and add 3 more sentences "
                     "that guide the listener's attention, without adding facts.")
    numbers = invented_numbers(story, facts)
    if numbers:
        found.append(f"It contains numbers that are not in the facts: {', '.join(numbers)}. Remove them.")
    banned = [b for b in THIN_BANNED if thin and b in story.lower()]
    if banned:
        found.append(f"It uses '{banned[0]}', which introduces something not in the facts. Remove any claim not in the facts.")
    return found


def write_story(stop, lang, area, note=None):
    thin = not stop.get("wiki") and not note  # only OSM tags to work with
    # Area articles only go to stops with their own facts; a thin stop would pin the area's facts on itself.
    facts, sources = facts_text(stop, [] if thin else area, note)
    model = config.THIN_STORY_MODEL if thin else config.OLLAMA_MODEL
    language = LANGUAGE_NAMES.get(lang, lang)
    min_words, max_words = word_range(thin)
    target = (min_words + max_words) // 2
    system = SYSTEM_PROMPT.format(
        language=language,
        min_words=min_words,
        max_words=max_words,
        target_words=target,
        mode_rules=(THIN_RULES if thin else RICH_RULES).format(language=language),
    )
    messages = [{"role": "system", "content": system},
                {"role": "user", "content": f"Facts:\n{facts}\n\nWrite the story in about {target} words "
                                            f"(never more than {max_words})."}]
    story = chat(messages, model)
    attempts = 1
    issues = problems(story, facts, thin)
    if issues:  # one retry, telling Gemma exactly what was wrong
        messages += [{"role": "assistant", "content": story},
                     {"role": "user", "content": "Rewrite the story. " + " ".join(issues) + " Follow every rule."}]
        retry = chat(messages, model)
        attempts = 2
        retry_issues = problems(retry, facts, thin)
        if len(retry_issues) <= len(issues):
            story, issues = retry, retry_issues
    return {
        "id": stop["id"],
        "story": story,
        "words": word_count(story),
        "attempts": attempts,
        "thin_facts": thin,
        "model": model,
        "problems": issues,
        "check_names": unknown_names(story, facts),
        "facts": facts,
        "sources": sources,
    }


def write_review(work_dir, stops, stories):
    lines = ["# Story review", "", "Read each story against its facts. Flagged words are capitalized words not found in the facts.", ""]
    for i, (stop, s) in enumerate(zip(stops, stories), 1):
        lines += [f"## {i}. {stop['name']}", "",
                  f"{s['words']} words, {s['attempts']} attempt(s), {s['model']}" + (" · thin facts" if s["thin_facts"] else "")
                  + (f" · PROBLEMS: {' '.join(s['problems'])}" if s["problems"] else "")
                  + (f" · check: {', '.join(s['check_names'])}" if s["check_names"] else ""), "",
                  "**Facts**", "", "```", s["facts"], "```", "", "**Story**", "", s["story"], ""]
    (work_dir / "review.md").write_text("\n".join(lines))


def run(work_dir, lang):
    stops = json.loads((work_dir / "stops_ranked.json").read_text())
    area_path = work_dir / "area.json"
    area = json.loads(area_path.read_text()) if area_path.exists() else []
    notes_path = config.NOTES_DIR / f"{work_dir.name}.json"
    notes = json.loads(notes_path.read_text()) if notes_path.exists() else {}
    stories = []
    for stop in stops:
        result = write_story(stop, lang, area, notes.get(stop["id"]))
        stories.append(result)
        flag = " PROBLEM: " + " ".join(result["problems"]) if result["problems"] else ""
        print(f"  {stop['name']}: {result['words']} words, {result['attempts']} attempt(s){flag}")
    (work_dir / "stories.json").write_text(json.dumps(stories, ensure_ascii=False, indent=2))
    write_review(work_dir, stops, stories)
    return stories


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--route", required=True)
    parser.add_argument("--lang", default=config.LANGUAGE)
    args = parser.parse_args()
    run(config.WORK_DIR / args.route, args.lang)
