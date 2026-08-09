#!/usr/bin/env python3
"""Offline tests for the pure functions in github_pr.py."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import github_pr as g  # noqa: E402


class MarkdownOrg(unittest.TestCase):
    def test_fenced_code_becomes_src(self):
        out = g.md_to_org("before\n```go\nx := 1\n```\nafter")
        self.assertIn("#+begin_src go", out)
        self.assertIn("x := 1", out)
        self.assertIn("#+end_src", out)

    def test_heading_becomes_bold_not_org_heading(self):
        out = g.md_to_org("## Design thoughts")
        self.assertEqual(out, "*Design thoughts*")
        self.assertFalse(out.startswith("* "))

    def test_star_bullets_become_dashes(self):
        self.assertEqual(g.md_to_org("* one\n* two"), "- one\n- two")

    def test_links_and_inline(self):
        out = g.md_to_org("see [docs](https://x.io) and `code` and **bold**")
        self.assertIn("[[https://x.io][docs]]", out)
        self.assertIn("~code~", out)
        self.assertIn("*bold*", out)

    def test_org_to_md_roundtrips_code_and_links(self):
        md = g.org_to_md("#+begin_src py\nprint(1)\n#+end_src\nsee [[https://x.io][docs]]")
        self.assertIn("```py", md)
        self.assertIn("[docs](https://x.io)", md)


class Conversations(unittest.TestCase):
    def _c(self, login, when, body="hi", cid=1):
        return {"databaseId": cid, "author": {"login": login},
                "createdAt": when, "body": body}

    def test_sorted_by_newest_reply(self):
        threads = [
            {"id": "T1", "isResolved": False, "isOutdated": False, "path": "a.py",
             "line": 1, "originalLine": 1,
             "comments": {"totalCount": 1, "nodes": [self._c("ann", "2024-01-01T00:00:00Z")]}},
            {"id": "T2", "isResolved": False, "isOutdated": False, "path": "b.py",
             "line": 2, "originalLine": 2,
             "comments": {"totalCount": 2, "nodes": [
                 self._c("ann", "2024-01-02T00:00:00Z", cid=2),
                 self._c("bob", "2024-01-05T00:00:00Z", cid=3)]}},
        ]
        convs = g.build_conversations(threads, [])
        # T2 has the newest reply (Jan 5) so it sorts first...
        self.assertEqual(convs[0]["thread_id"], "T2")
        # ...but its heading date is its FIRST comment (Jan 2), and reply_to is
        # the root comment's id.
        self.assertEqual(convs[0]["first"][:10], "2024-01-02")
        self.assertEqual(convs[0]["reply_to"], 2)

    def test_ghost_author_and_render(self):
        threads = [{"id": "T", "isResolved": True, "isOutdated": False, "path": "a.py",
                    "line": 3, "originalLine": 3,
                    "comments": {"totalCount": 1, "nodes": [
                        {"databaseId": 9, "author": None, "url": "https://gh/c9",
                         "createdAt": "2024-01-01T00:00:00Z", "body": "x"}]}}]
        convs = g.build_conversations(threads, [])
        pr = {"owner": "o", "repo": "r", "number": 5, "url": "u", "title": "t"}
        g.annotate_local_links(convs, pr, None)          # no worktree -> browse only
        org = g.render_org(pr, convs)
        self.assertIn("* a.py:3 :resolved:", org)       # file:line + resolved tag
        self.assertRegex(org, r"\*\* \d{4}-\d\d-\d\d \d\d:\d\d ghost")  # ** date time author
        self.assertIn(":GH_REPLY_TO: 9", org)
        self.assertIn(":GH_STATE: resolved", org)
        self.assertIn("[[https://gh/c9][browse thread]]", org)
        self.assertIn("[[https://gh/c9][🔗 view comment on GitHub]]", org)


class Links(unittest.TestCase):
    CONV = {"kind": "review", "path": "a.py", "line": 3,
            "orig_oid": "abc1234def", "orig_line": 2,
            "url": "https://gh/pull/1#discussion_r9"}

    def test_all_links_when_local_matches(self):
        links = g.conversation_links(self.CONV, "/repo",
                                     file_exists=lambda p: True,
                                     blob_exists=lambda oid, path: True)
        self.assertIn("[[file:/repo/a.py::3][local file]]", links)
        self.assertIn("[[ghpr-rev:abc1234def:a.py::2][file @abc1234]]", links)
        self.assertIn("[[https://gh/pull/1#discussion_r9][browse thread]]", links)

    def test_only_browse_when_no_local_checkout(self):
        links = g.conversation_links(self.CONV, None,
                                     file_exists=lambda p: True,
                                     blob_exists=lambda oid, path: True)
        self.assertEqual(links, ["[[https://gh/pull/1#discussion_r9][browse thread]]"])

    def test_no_local_link_when_file_missing(self):
        links = g.conversation_links(self.CONV, "/repo",
                                     file_exists=lambda p: False,
                                     blob_exists=lambda oid, path: False)
        self.assertFalse(any("local file" in x for x in links))
        self.assertFalse(any("ghpr-rev" in x for x in links))

    def test_remote_matches(self):
        for line in ("origin\tgit@github.com:cli/cli.git (fetch)",
                     "origin\thttps://github.com/cli/cli (push)",
                     "up\thttps://github.com/CLI/CLI.git (fetch)"):
            self.assertTrue(g._remote_matches(line, "cli/cli"), line)
        self.assertFalse(g._remote_matches("o\tgit@github.com:other/repo.git (fetch)", "cli/cli"))

    def test_fmt_dt_shape(self):
        self.assertRegex(g._fmt_dt("2024-04-29T14:59:46Z"), r"^2024-04-\d\d \d\d:\d\d$")
        self.assertEqual(g._fmt_dt("garbage"), "garbage")


class PlanFromBuffer(unittest.TestCase):
    ORG = """#+GITHUB_PR: repo=o/r number=7
#+GITHUB_URL: https://github.com/o/r/pull/7

* 2024-01-01  a.py:1  [open]
:PROPERTIES:
:GH_KIND: review
:GH_THREAD: T1
:GH_REPLY_TO: 100
:GH_PATH: a.py
:END:
** ann
:PROPERTIES:
:GH_COMMENT: 100
:GH_CREATED: 2024-01-01T00:00:00Z
:END:
what about tests?
**
sure, added them.

* 2024-01-02  General discussion
:PROPERTIES:
:GH_KIND: issue
:END:
** bob
:PROPERTIES:
:GH_COMMENT: 200
:GH_CREATED: 2024-01-02T00:00:00Z
:END:
looks good.
"""

    def test_detects_only_the_empty_reply(self):
        plan = g.compute_plan(g.parse_org(self.ORG))
        self.assertEqual(plan["problems"], [])
        self.assertEqual(len(plan["actions"]), 1)
        a = plan["actions"][0]
        self.assertEqual(a["type"], "review_reply")
        self.assertEqual(a["reply_to"], "100")
        self.assertEqual(a["body"], "sure, added them.")

    def test_empty_reply_body_is_a_problem(self):
        org = self.ORG.replace("sure, added them.", "")
        plan = g.compute_plan(g.parse_org(org))
        self.assertEqual(plan["actions"], [])
        self.assertTrue(any("empty reply" in p for p in plan["problems"]))

    def test_missing_header_is_a_problem(self):
        plan = g.compute_plan(g.parse_org("* x\n** \nhello"))
        self.assertTrue(any("#+GITHUB_PR" in p for p in plan["problems"]))

    def test_resolve_via_d_marker(self):
        # a [d] on an existing message header resolves the thread (+ the reply)
        plan = g.compute_plan(g.parse_org(self.ORG.replace("** ann", "** ann [d]")))
        types = [a["type"] for a in plan["actions"]]
        self.assertIn("resolve_thread", types)
        self.assertIn("review_reply", types)
        r = next(a for a in plan["actions"] if a["type"] == "resolve_thread")
        self.assertEqual(r["thread_id"], "T1")

    def test_already_resolved_d_is_noop(self):
        org = (self.ORG.replace(":GH_THREAD: T1", ":GH_THREAD: T1\n:GH_STATE: resolved")
                       .replace("** ann", "** ann [d]"))
        plan = g.compute_plan(g.parse_org(org))
        self.assertFalse(any(a["type"] == "resolve_thread" for a in plan["actions"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
