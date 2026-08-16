#!/usr/bin/env python3
"""Offline unit tests for the pure logic in timesheet.py (no network/keyring)."""
import unittest

import timesheet as T


class TimeMath(unittest.TestCase):
    def test_add_minutes(self):
        self.assertEqual(T._add_minutes("13:00", 120), "15:00")
        self.assertEqual(T._add_minutes("09:30", 45), "10:15")
        self.assertEqual(T._add_minutes("23:30", 60), "00:30")

    def test_fmt_hm(self):
        self.assertEqual(T._fmt_hm(90), "1:30")
        self.assertEqual(T._fmt_hm(5), "0:05")


class NormalizeTimelog(unittest.TestCase):
    def test_start_from_user_perspective(self):
        raw = {"id": "7230526", "todo-item-id": "16705771", "project-id": "366955",
               "date": "2026-07-16T15:42:00Z", "dateUserPerspective": "2026-07-16T11:42:00Z",
               "has-start-time": "1", "hours": "0", "minutes": "30", "isbillable": "1",
               "description": "some task\neven multiline"}
        n = T.normalize_timelog(raw)
        self.assertEqual(n["id"], 7230526)
        self.assertEqual(n["task_id"], 16705771)
        self.assertEqual(n["date"], "2026-07-16")   # user-perspective date, not UTC
        self.assertEqual(n["start"], "11:42")        # from dateUserPerspective, not a "time" field
        self.assertEqual(n["minutes"], 30)
        self.assertTrue(n["billable"])
        self.assertEqual(n["description"], "some task\neven multiline")

    def test_no_start_time(self):
        raw = {"id": "1", "todo-item-id": "2", "project-id": "3",
               "dateUserPerspective": "2026-07-16T00:00:00Z", "has-start-time": "0",
               "hours": "1", "minutes": "15", "isbillable": "0", "description": "d"}
        n = T.normalize_timelog(raw)
        self.assertIsNone(n["start"])
        self.assertEqual(n["minutes"], 75)
        self.assertFalse(n["billable"])


class RenderLine(unittest.TestCase):
    def test_start_end_with_id(self):
        log = {"id": 87654321, "date": "2026-06-10", "start": "13:00", "minutes": 120,
               "description": "started working"}
        self.assertEqual(T.render_log_line(log), ["- 87654321 2026-06-10 13:00 15:00 started working"])

    def test_duration_and_multiline(self):
        log = {"id": 7, "date": "2026-06-13", "start": None, "minutes": 90,
               "description": "first\nsecond"}
        self.assertEqual(T.render_log_line(log), ["- 7 2026-06-13 =1:30 first", "  second"])


def _tree(logs, task_prop=":TASK_ID: 300\n", tl_prop=":TASKLIST_ID: 200\n",
          task_title="T", tl_name="L"):
    return (
        "#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=363603\n"
        "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n"
        "** " + tl_name + "\n:PROPERTIES:\n" + tl_prop + ":END:\n"
        "*** " + task_title + "\n:PROPERTIES:\n" + task_prop + ":END:\n" + logs
    )


class ParseBasics(unittest.TestCase):
    def test_header_tree_and_continuation(self):
        p = T.parse_org(_tree("- 42 2026-06-10 13:00 15:00 did\n  more\n"))
        self.assertEqual(p["meta"]["from"], "2026-06-01")
        self.assertEqual(p["meta"]["user"], "363603")
        log = p["projects"][0]["tasklists"][0]["tasks"][0]["logs"][0]
        self.assertEqual((log["id"], log["start"], log["minutes"], log["description"]),
                         (42, "13:00", 120, "did\nmore"))
        self.assertEqual(log["task_id"], 300)

    def test_problem_backwards_time(self):
        p = T.parse_org(_tree("- 2026-06-11 15:00 13:00 bad\n"))
        self.assertTrue(any("not after start" in x for x in p["problems"]))

    def test_hhmm_times_parse_and_normalise(self):
        p = T.parse_org(_tree("- 2026-06-10 0900 1330 [d] compact\n"))
        log = p["projects"][0]["tasklists"][0]["tasks"][0]["logs"][0]
        self.assertEqual(log["start"], "09:00")       # HHMM normalised to HH:MM
        self.assertEqual(log["minutes"], 270)          # 09:00 -> 13:30
        self.assertEqual(log["description"], "compact")
        self.assertTrue(log["done"])                   # [d] flag captured

    def test_done_flag_defaults_false(self):
        p = T.parse_org(_tree("- 2026-06-10 09:00 10:00 plain\n"))
        self.assertFalse(p["projects"][0]["tasklists"][0]["tasks"][0]["logs"][0]["done"])


class TimeToken(unittest.TestCase):
    def test_to_minutes_both_forms(self):
        self.assertEqual(T._to_minutes("09:00"), 540)
        self.assertEqual(T._to_minutes("0900"), 540)
        self.assertEqual(T._to_minutes("900"), 540)   # 3-digit HMM
        self.assertEqual(T._to_minutes("1345"), 825)

    def test_norm_hm(self):
        self.assertEqual(T._norm_hm("900"), "09:00")
        self.assertEqual(T._norm_hm("1345"), "13:45")
        self.assertEqual(T._norm_hm("9:05"), "09:05")


class RoundTrip(unittest.TestCase):
    def test_render_then_parse(self):
        projects = [{"id": 100, "name": "Proj"}]
        tasklists = [{"id": 200, "name": "List", "project_id": 100}]
        tasks = [{"id": 300, "title": "Task", "tasklist_id": 200, "project_id": 100}]
        logs = [{"id": 42, "task_id": 300, "project_id": 100, "date": "2026-06-10",
                 "start": "13:00", "minutes": 120, "description": "one\ntwo", "billable": True}]
        meta = {"from": "2026-06-01", "to": "2026-06-30", "user_id": 363603}
        p = T.parse_org(T.render_org(projects, tasklists, tasks, logs, meta))
        out = p["projects"][0]["tasklists"][0]["tasks"][0]["logs"][0]
        self.assertEqual((out["id"], out["start"], out["minutes"], out["description"]),
                         (42, "13:00", 120, "one\ntwo"))

    def test_serialize_reparse_stable(self):
        p1 = T.parse_org(_tree("- 42 2026-06-10 13:00 15:00 hi\n"))
        text = T.serialize_parsed(p1)
        p2 = T.parse_org(text)
        self.assertEqual(p2["projects"][0]["tasklists"][0]["id"], 200)
        self.assertEqual(p2["projects"][0]["tasklists"][0]["tasks"][0]["id"], 300)
        self.assertEqual(p2["projects"][0]["tasklists"][0]["tasks"][0]["logs"][0]["id"], 42)

    def test_serialize_fills_created_id(self):
        p = T.parse_org(_tree("- 2026-06-10 13:00 14:00 fresh\n", task_prop=""))  # new task
        tk = p["projects"][0]["tasklists"][0]["tasks"][0]
        self.assertIsNone(tk["id"])
        tk["id"] = 999                 # simulate a successful create
        tk["logs"][0]["id"] = 555
        p2 = T.parse_org(T.serialize_parsed(p))
        tk2 = p2["projects"][0]["tasklists"][0]["tasks"][0]
        self.assertEqual(tk2["id"], 999)
        self.assertEqual(tk2["logs"][0]["id"], 555)


class Subtasks(unittest.TestCase):
    """Headings demoted below a task (**** or deeper) are subtasks, nesting to any depth."""

    def _tree(self, extra=""):
        return (
            "#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=363603\n"
            "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n"
            "** L\n:PROPERTIES:\n:TASKLIST_ID: 200\n:END:\n"
            "*** Task\n:PROPERTIES:\n:TASK_ID: 300\n:END:\n" + extra
        )

    def test_parse_nested_subtasks(self):
        text = self._tree(
            "**** Sub A\n:PROPERTIES:\n:TASK_ID: 400\n:END:\n"
            "***** Sub A1\n:PROPERTIES:\n:TASK_ID: 410\n:END:\n"
            "**** Sub B\n:PROPERTIES:\n:TASK_ID: 500\n:END:\n"
        )
        task = T.parse_org(text)["projects"][0]["tasklists"][0]["tasks"][0]
        self.assertEqual(task["id"], 300)
        self.assertEqual([s["title"] for s in task["subtasks"]], ["Sub A", "Sub B"])
        subA = task["subtasks"][0]
        self.assertEqual([s["id"] for s in subA["subtasks"]], [410])   # A1 nests under A
        self.assertIs(subA["subtasks"][0]["parent"], subA)             # back-ref wired
        self.assertEqual(task["subtasks"][1]["subtasks"], [])          # B has no children

    def test_log_attaches_to_deepest_subtask(self):
        text = self._tree(
            "**** Sub\n:PROPERTIES:\n:TASK_ID: 400\n:END:\n"
            "- 2026-06-10 09:00 10:00 on the subtask\n"
        )
        task = T.parse_org(text)["projects"][0]["tasklists"][0]["tasks"][0]
        self.assertEqual(task["logs"], [])                       # not on the parent
        log = task["subtasks"][0]["logs"][0]
        self.assertEqual((log["task_id"], log["description"]), (400, "on the subtask"))

    def test_subtask_without_parent_task_is_a_problem(self):
        text = (
            "#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=363603\n"
            "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n"
            "** L\n:PROPERTIES:\n:TASKLIST_ID: 200\n:END:\n"
            "**** Orphan sub\n"          # level 4 with no level-3 task above it
        )
        self.assertTrue(any("no parent task" in p for p in T.parse_org(text)["problems"]))

    def test_render_round_trips_subtasks(self):
        projects = [{"id": 100, "name": "P"}]
        tasklists = [{"id": 200, "name": "L", "project_id": 100}]
        tasks = [
            {"id": 300, "title": "Task", "tasklist_id": 200, "project_id": 100, "parent_id": None},
            {"id": 400, "title": "Sub", "tasklist_id": 200, "project_id": 100, "parent_id": 300},
            {"id": 410, "title": "Deep", "tasklist_id": 200, "project_id": 100, "parent_id": 400},
        ]
        logs = [{"id": 42, "task_id": 410, "project_id": 100, "date": "2026-06-10",
                 "start": "13:00", "minutes": 60, "description": "d", "billable": True}]
        meta = {"from": "2026-06-01", "to": "2026-06-30", "user_id": 363603}
        text = T.render_org(projects, tasklists, tasks, logs, meta)
        self.assertIn("*** Task", text)
        self.assertIn("**** Sub", text)
        self.assertIn("***** Deep", text)
        # re-parsing rebuilds the same nesting and keeps the deep log
        task = T.parse_org(text)["projects"][0]["tasklists"][0]["tasks"][0]
        self.assertEqual(task["subtasks"][0]["subtasks"][0]["id"], 410)
        self.assertEqual(task["subtasks"][0]["subtasks"][0]["logs"][0]["id"], 42)

    def test_serialize_reparse_stable_with_subtasks(self):
        p1 = T.parse_org(self._tree(
            "**** Sub\n:PROPERTIES:\n:TASK_ID: 400\n:END:\n"
            "- 42 2026-06-10 13:00 14:00 hi\n"))
        p2 = T.parse_org(T.serialize_parsed(p1))
        sub = p2["projects"][0]["tasklists"][0]["tasks"][0]["subtasks"][0]
        self.assertEqual((sub["id"], sub["logs"][0]["id"]), (400, 42))

    def test_snapshot_includes_subtasks(self):
        p = T.parse_org(self._tree("**** Sub\n:PROPERTIES:\n:TASK_ID: 400\n:END:\n"))
        snap = T.build_snapshot_from_parsed(p)
        self.assertEqual(snap["tasks"], {"300": "Task", "400": "Sub"})

    def test_plan_creates_subtask_under_existing_task(self):
        # a new heading demoted under existing task 300 -> create_subtask on parent 300
        plan = T.compute_plan(T.parse_org(self._tree("**** Fresh Sub\n")),
                              {"logs": {}, "tasks": {"300": "Task"}}, 363603)
        self.assertEqual([a["type"] for a in plan["actions"]], ["create_subtask"])
        self.assertEqual(plan["actions"][0]["parent"], 300)   # existing parent id

    def test_plan_rename_subtask(self):
        snap = {"logs": {}, "tasks": {"300": "Task", "400": "Old Sub"}}
        plan = T.compute_plan(
            T.parse_org(self._tree("**** New Sub\n:PROPERTIES:\n:TASK_ID: 400\n:END:\n")),
            snap, 363603)
        self.assertEqual([a["type"] for a in plan["actions"]], ["update_task"])
        act = plan["actions"][0]
        self.assertEqual(act["title"], "New Sub")
        self.assertIn("subtask", act["summary"])
        self.assertIn("rename", act["summary"])

    def test_plan_new_task_then_new_subtask_orders_parent_first(self):
        # brand-new task (no id) with a brand-new subtask + a log on the subtask:
        # create_task must precede create_subtask, which must target the task's ref.
        text = (
            "#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=363603\n"
            "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n"
            "** L\n:PROPERTIES:\n:TASKLIST_ID: 200\n:END:\n"
            "*** New Task\n"
            "**** New Sub\n"
            "- 2026-06-10 09:00 10:00 deep\n"
        )
        actions = T.compute_plan(T.parse_org(text), {"logs": {}}, 363603)["actions"]
        self.assertEqual([a["type"] for a in actions],
                         ["create_task", "create_subtask", "create_timelog"])
        task_ref = actions[0]["ref"]
        self.assertEqual(actions[1]["parent"], {"ref": task_ref})   # subtask -> task ref
        self.assertEqual(actions[2]["task"], {"ref": actions[1]["ref"]})  # log -> subtask ref

    def test_done_marker_completes_subtask(self):
        plan = T.compute_plan(
            T.parse_org(self._tree(
                "**** Sub\n:PROPERTIES:\n:TASK_ID: 400\n:END:\n"
                "- 2026-06-10 09:00 10:00 [d] wrap\n")),
            {"logs": {}}, 363603)
        complete = next(a for a in plan["actions"] if a["type"] == "complete_task")
        self.assertEqual(complete["task"], 400)   # the subtask, not its parent


class Plan(unittest.TestCase):
    def _plan(self, text, snapshot):
        return T.compute_plan(T.parse_org(text), snapshot, user_id=363603)

    def test_create_new_log(self):
        plan = self._plan(_tree("- 2026-06-10 13:00 15:00 fresh\n"), {"logs": {}})
        self.assertEqual([a["type"] for a in plan["actions"]], ["create_timelog"])
        body = plan["actions"][0]["body"]
        self.assertEqual((body["date"], body["time"], body["hours"], body["minutes"]),
                         ("20260610", "13:00", 2, 0))

    def test_unchanged_no_action(self):
        snap = {"logs": {"42": {"date": "2026-06-10", "start": "13:00", "minutes": 120,
                                "description": "same"}}}
        self.assertEqual(self._plan(_tree("- 42 2026-06-10 13:00 15:00 same\n"), snap)["actions"], [])

    def test_edit_updates(self):
        snap = {"logs": {"42": {"date": "2026-06-10", "start": "13:00", "minutes": 120,
                                "description": "old"}}}
        plan = self._plan(_tree("- 42 2026-06-10 13:00 16:00 new\n"), snap)
        self.assertEqual([a["type"] for a in plan["actions"]], ["update_timelog"])
        self.assertEqual(plan["actions"][0]["body"]["hours"], 3)

    def test_done_marker_completes_task_on_create(self):
        plan = self._plan(_tree("- 2026-06-10 13:00 15:00 [d] wrap up\n"), {"logs": {}})
        self.assertEqual([a["type"] for a in plan["actions"]],
                         ["create_timelog", "complete_task"])
        self.assertEqual(plan["actions"][1]["task"], 300)   # existing task id

    def test_done_marker_on_new_task_targets_ref(self):
        # brand-new task (no TASK_ID) + a [d] log: complete must target the new ref
        plan = self._plan(_tree("- 2026-06-10 13:00 15:00 [d] x\n", task_prop=""), {"logs": {}})
        types = [a["type"] for a in plan["actions"]]
        self.assertEqual(types, ["create_task", "create_timelog", "complete_task"])
        newtask = next(a for a in plan["actions"] if a["type"] == "create_task")
        self.assertEqual(plan["actions"][-1]["task"], {"ref": newtask["ref"]})

    def test_done_marker_completes_even_when_log_unchanged(self):
        # only [d] was added to an otherwise-identical log: no update, still complete
        snap = {"logs": {"42": {"date": "2026-06-10", "start": "13:00", "minutes": 120,
                                "description": "same"}}}
        plan = self._plan(_tree("- 42 2026-06-10 13:00 15:00 [d] same\n"), snap)
        self.assertEqual([a["type"] for a in plan["actions"]], ["complete_task"])

    def test_removed_deletes(self):
        snap = {"logs": {"42": {"date": "2026-06-10", "start": "13:00", "minutes": 120,
                                "description": "gone"}}}
        plan = self._plan(_tree(""), snap)
        self.assertEqual([a["type"] for a in plan["actions"]], ["delete_timelog"])
        self.assertEqual(plan["actions"][0]["id"], 42)

    def test_rename_task_and_list(self):
        snap = {"logs": {}, "tasklists": {"200": "Old List"}, "tasks": {"300": "Old Task"}}
        plan = self._plan(_tree("", tl_name="New List", task_title="New Task"), snap)
        types = {a["type"] for a in plan["actions"]}
        self.assertEqual(types, {"update_tasklist", "update_task"})
        byt = {a["type"]: a for a in plan["actions"]}
        self.assertEqual(byt["update_task"]["title"], "New Task")
        self.assertEqual(byt["update_tasklist"]["name"], "New List")

    def test_full_order_lists_tasks_renames_logs_deletes(self):
        # new list w/ new task w/ log; existing task renamed w/ new log; plus a delete
        text = (
            "#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=363603\n"
            "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n"
            "** Existing\n:PROPERTIES:\n:TASKLIST_ID: 200\n:END:\n"
            "*** Renamed Task\n:PROPERTIES:\n:TASK_ID: 300\n:END:\n"
            "- 2026-06-10 09:00 10:00 log on existing\n"
            "** Brand New List\n"
            "*** Brand New Task\n"
            "- 2026-06-11 09:00 10:00 deep\n"
        )
        snap = {"logs": {"77": {"date": "2026-06-01", "start": "09:00", "minutes": 60,
                                "description": "x"}},
                "tasklists": {"200": "Existing"}, "tasks": {"300": "Old Name"}}
        actions = T.compute_plan(T.parse_org(text), snap, 363603)["actions"]
        self.assertEqual([a["type"] for a in actions],
                         ["create_tasklist", "create_task", "update_task",
                          "create_timelog", "create_timelog", "delete_timelog"])
        # the deep log must target the freshly-created task ref
        newtask = next(a for a in actions if a["type"] == "create_task")
        deeplog = [a for a in actions if a["type"] == "create_timelog"][-1]
        self.assertEqual(deeplog["task"], {"ref": newtask["ref"]})
        # the new task must target the freshly-created list ref
        newlist = next(a for a in actions if a["type"] == "create_tasklist")
        self.assertEqual(newtask["tasklist"], {"ref": newlist["ref"]})

    def test_public_action_strips_private_keys(self):
        plan = self._plan(_tree("- 2026-06-10 13:00 15:00 x\n"), {"logs": {}})
        pub = T.public_action(plan["actions"][0])
        self.assertNotIn("_obj", pub)
        self.assertIn("summary", pub)


class HiddenProjects(unittest.TestCase):
    def test_parse_hidden_header(self):
        p = T.parse_org("#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=1\n"
                        "#+TEAMWORK_HIDDEN: 5 6\n* P\n")
        self.assertEqual(p["meta"]["hidden"], [5, 6])

    def test_hidden_absent_is_none(self):
        p = T.parse_org("#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=1\n* P\n")
        self.assertIsNone(p["meta"]["hidden"])

    def test_reconcile_deleted_heading_becomes_hidden(self):
        prefs = {"hidden": {}, "shown": [1, 2, 3]}
        self.assertEqual(T.reconcile_hidden(prefs, {"1", "3"}, set()), {"2"})

    def test_reconcile_unhide_via_property(self):
        prefs = {"hidden": {"9": "x"}, "shown": [1]}
        self.assertEqual(T.reconcile_hidden(prefs, {"1"}, set()), set())

    def test_reconcile_manual_add_via_property(self):
        prefs = {"hidden": {}, "shown": [1, 2]}
        self.assertEqual(T.reconcile_hidden(prefs, {"1", "2"}, {"2"}), {"2"})

    def test_reconcile_no_prev_keeps_prefs(self):
        prefs = {"hidden": {"9": "x"}, "shown": [1]}
        self.assertEqual(T.reconcile_hidden(prefs, None, None), {"9"})

    def test_reconcile_empty_prev_does_not_hide_everything(self):
        # A buffer that rendered NO project headings (all-hidden/placeholder) must
        # not be read as "the user deleted every project" — that stranded the user
        # with zero visible projects and no way back.
        prefs = {"hidden": {}, "shown": [1, 2, 3]}
        self.assertEqual(T.reconcile_hidden(prefs, set(), set()), set())

    def test_reconcile_empty_prev_still_honours_edited_header(self):
        # Emptying the #+TEAMWORK_HIDDEN: line un-hides even from the all-hidden
        # state (header is authoritative; no spurious deletions get added back).
        prefs = {"hidden": {"1": "a", "2": "b"}, "shown": []}
        self.assertEqual(T.reconcile_hidden(prefs, set(), set()), set())

    def test_header_round_trips_hidden(self):
        text = T.render_org([{"id": 1, "name": "P"}], [], [], [],
                            {"from": "2026-06-01", "to": "2026-06-30", "user_id": 1},
                            hidden_names={"366955": "another project"})
        self.assertIn("#+TEAMWORK_HIDDEN: 366955", text)
        self.assertEqual(T.parse_org(text)["meta"]["hidden"], [366955])

    def test_delete_guard_keeps_absent_project_logs(self):
        snap = {"logs": {
            "42": {"project_id": 100, "date": "2026-06-10", "start": "13:00",
                   "minutes": 60, "description": "gone from present project"},
            "77": {"project_id": 500, "date": "2026-06-10", "start": "09:00",
                   "minutes": 60, "description": "belongs to a hidden project"},
        }}
        plan = T.compute_plan(T.parse_org(_tree("")), snap, 363603)
        dels = {a["id"] for a in plan["actions"] if a["type"] == "delete_timelog"}
        self.assertEqual(dels, {42})   # 100 present -> delete; 500 absent -> kept


class Accounts(unittest.TestCase):
    """Multi-account: header round-trip, slug, and per-account snapshot keying."""

    def test_slug(self):
        self.assertEqual(T._slug("work"), "work")
        self.assertEqual(T._slug("Client X / 2"), "Client_X_2")
        self.assertEqual(T._slug(""), "default")

    def test_parse_account_header(self):
        p = T.parse_org("#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=1\n"
                        "#+TEAMWORK_ACCOUNT: client x\n* P\n")
        self.assertEqual(p["meta"]["account"], "client x")

    def test_account_absent_is_none(self):
        p = T.parse_org("#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=1\n* P\n")
        self.assertIsNone(p["meta"]["account"])

    def test_render_includes_account_and_round_trips(self):
        text = T.render_org([{"id": 1, "name": "P"}], [], [], [],
                            {"from": "2026-06-01", "to": "2026-06-30", "user_id": 1,
                             "account": "work"})
        self.assertIn("#+TEAMWORK_ACCOUNT: work", text)
        self.assertEqual(T.parse_org(text)["meta"]["account"], "work")

    def test_render_omits_account_header_when_absent(self):
        text = T.render_org([{"id": 1, "name": "P"}], [], [], [],
                            {"from": "2026-06-01", "to": "2026-06-30", "user_id": 1})
        self.assertNotIn("#+TEAMWORK_ACCOUNT", text)

    def test_serialize_preserves_account(self):
        p = T.parse_org("#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=1\n"
                        "#+TEAMWORK_ACCOUNT: work\n"
                        "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n")
        self.assertIn("#+TEAMWORK_ACCOUNT: work", T.serialize_parsed(p))

    def test_snapshot_path_keyed_by_account(self):
        base = T.snapshot_path("2026-06-01", "2026-06-30")
        acct = T.snapshot_path("2026-06-01", "2026-06-30", "work")
        self.assertEqual(base.name, "snapshot_2026-06-01_2026-06-30.json")  # unchanged
        self.assertNotEqual(base.name, acct.name)
        self.assertIn("work", acct.name)


class Synthesize(unittest.TestCase):
    """Completed/archived lists+tasks are unfetched; rebuild them from the log."""

    def _log(self, **kw):
        base = {"id": 21061789, "task_id": 50137, "task_name": "Featured Image field on dashboard",
                "tasklist_id": 3999, "tasklist_name": "Sprint W25", "project_id": 1354364,
                "project_name": "Elvou App & Web", "date": "2026-06-17", "start": "14:30",
                "minutes": 30, "description": "x", "billable": True}
        base.update(kw)
        return base

    def test_reattaches_completed_task_and_list(self):
        projects = [{"id": 1354364, "name": "Elvou App & Web"}]
        tasklists, tasks = [], []            # both omitted because completed
        T.synthesize_missing(projects, tasklists, tasks, [self._log()])
        self.assertEqual([(t["id"], t["name"]) for t in tasklists], [(3999, "Sprint W25")])
        self.assertEqual([(t["id"], t["title"]) for t in tasks],
                         [(50137, "Featured Image field on dashboard")])

    def test_synthesizes_missing_project(self):
        projects, tasklists, tasks = [], [], []
        T.synthesize_missing(projects, tasklists, tasks, [self._log()])
        self.assertEqual([p["id"] for p in projects], [1354364])

    def test_render_places_log_under_heading_not_dropped(self):
        projects = [{"id": 1354364, "name": "Elvou App & Web"}]
        tasklists, tasks = [], []
        logs = [self._log()]
        T.synthesize_missing(projects, tasklists, tasks, logs)
        text = T.render_org(projects, tasklists, tasks, logs,
                            {"from": "2026-06-01", "to": "2026-06-30", "user_id": 1})
        self.assertIn("** Sprint W25", text)
        self.assertIn("*** Featured Image field on dashboard", text)
        self.assertIn("2026-06-17 14:30 15:00", text)
        self.assertNotIn("no task in the pulled tree", text)

    def test_unmatched_log_is_orphaned_not_dropped(self):
        projects, tasklists, tasks = [{"id": 1, "name": "P"}], [], []
        logs = [self._log(project_id=1, tasklist_id=0, task_id=999, task_name="", tasklist_name="")]
        T.synthesize_missing(projects, tasklists, tasks, logs)
        text = T.render_org(projects, tasklists, tasks, logs,
                            {"from": "2026-06-01", "to": "2026-06-30", "user_id": 1})
        self.assertIn("no task in the pulled tree", text)  # visible, not silently dropped


class Pagination(unittest.TestCase):
    """paged() must fetch ALL pages even when the endpoint caps page size."""

    def _stub(self, pages, headers):
        class Stub:
            def __init__(s):
                s._last_headers = headers
                s.requested = []

            def get(s, path, page=1, pageSize=250, **kw):
                s.requested.append(page)
                return pages[page - 1] if page - 1 < len(pages) else {"items": []}
        return Stub()

    def test_uses_x_pages_when_first_page_is_short(self):
        # endpoint caps at 2/page but we asked for 250; header says 3 pages.
        pages = [{"items": [1, 2]}, {"items": [3, 4]}, {"items": [5]}]
        stub = self._stub(pages, {"X-Pages": "3"})
        got = T.Client.paged(stub, "/time_entries.json", "items")
        self.assertEqual(got, [1, 2, 3, 4, 5])          # not truncated at page 1
        self.assertEqual(stub.requested, [1, 2, 3])

    def test_fallback_without_header(self):
        pages = [{"items": list(range(250))}, {"items": [1, 2]}]
        stub = self._stub(pages, {})                    # no X-Pages header
        got = T.Client.paged(stub, "/x.json", "items")
        self.assertEqual(len(got), 252)

    def test_single_short_page(self):
        stub = self._stub([{"items": [1, 2, 3]}], {"X-Pages": "1"})
        self.assertEqual(T.Client.paged(stub, "/x.json", "items"), [1, 2, 3])
        self.assertEqual(stub.requested, [1])


class _FakeClient:
    def __init__(self, fail_task=0, fail_log=0):
        self.fail_task, self.fail_log = fail_task, fail_log
        self._tid, self._lid = 1000, 5000
        self.completed = []
        self.moved = []

    def create_tasklist(self, pid, name):
        self._tid += 1
        return self._tid

    def create_task(self, tlid, title, description=None):
        if self.fail_task > 0:
            self.fail_task -= 1
            raise RuntimeError("boom task")
        self._tid += 1
        return self._tid

    def create_subtask(self, parent_id, title, description=None):
        self._tid += 1
        return self._tid

    def delete_task(self, task_id):
        pass

    def delete_tasklist(self, tasklist_id):
        pass

    def create_timelog(self, tkid, body):
        if self.fail_log > 0:
            self.fail_log -= 1
            raise RuntimeError("boom log")
        self._lid += 1
        return self._lid

    def update_task(self, *a):
        pass

    def move_task(self, task_id, tasklist_id=None, parent_id=None):
        self.moved.append((task_id, tasklist_id, parent_id))

    def complete_task(self, task_id):
        self.completed.append(task_id)

    def update_tasklist(self, *a):
        pass

    def update_timelog(self, *a):
        pass

    def delete_timelog(self, *a):
        pass


class ApplyStream(unittest.TestCase):
    def setUp(self):
        T.BACKOFF_BASE = 0  # no real sleeping in tests

    def _run(self, text, snapshot, client):
        import io
        import json as _json
        import tempfile
        import contextlib
        parsed = T.parse_org(text)
        plan = T.compute_plan(parsed, snapshot, 363603)
        out = tempfile.NamedTemporaryFile("w+", suffix=".org", delete=False).name
        snap = tempfile.NamedTemporaryFile("w+", suffix=".json", delete=False).name
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            T.apply_stream(plan, client, parsed, out, snap)
        events = [_json.loads(l) for l in buf.getvalue().splitlines() if l.strip()]
        reparsed = T.parse_org(open(out).read())
        return events, reparsed

    def test_retry_then_success_fills_ids(self):
        text = _tree("- 2026-06-10 13:00 14:00 x\n", task_prop="")  # new task + new log
        events, re = self._run(text, {"logs": {}}, _FakeClient(fail_log=2))
        kinds = [(e["event"], e.get("idx"), e.get("attempt")) for e in events]
        self.assertIn(("retry", 1, 1), kinds)
        self.assertIn(("retry", 1, 2), kinds)
        done = events[-1]
        self.assertEqual((done["event"], done["aborted"], done["applied"]), ("done", False, 2))
        tk = re["projects"][0]["tasklists"][0]["tasks"][0]
        self.assertIsNotNone(tk["id"])            # task create folded in
        self.assertIsNotNone(tk["logs"][0]["id"])  # log create folded in

    def test_abort_keeps_unapplied(self):
        text = _tree("- 2026-06-10 13:00 14:00 x\n", task_prop="")
        events, re = self._run(text, {"logs": {}}, _FakeClient(fail_task=99))
        fail = next(e for e in events if e["event"] == "fail")
        self.assertEqual(fail["idx"], 0)
        done = events[-1]
        self.assertEqual((done["aborted"], done["applied"]), (True, 0))
        # dependent log never ran; task stays id-less so a retry re-creates it
        tk = re["projects"][0]["tasklists"][0]["tasks"][0]
        self.assertIsNone(tk["id"])
        self.assertIsNone(tk["logs"][0]["id"])

    def test_apply_creates_subtask_and_folds_id(self):
        # new task -> new subtask -> log on the subtask; ids fold back into the tree
        text = (
            "#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=363603\n"
            "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n"
            "** L\n:PROPERTIES:\n:TASKLIST_ID: 200\n:END:\n"
            "*** New Task\n"
            "**** New Sub\n"
            "- 2026-06-10 09:00 10:00 deep\n"
        )
        events, re = self._run(text, {"logs": {}}, _FakeClient())
        self.assertEqual(events[-1]["applied"], 3)             # task + subtask + log
        task = re["projects"][0]["tasklists"][0]["tasks"][0]
        sub = task["subtasks"][0]
        self.assertIsNotNone(task["id"])                       # parent task created
        self.assertIsNotNone(sub["id"])                        # subtask created
        self.assertNotEqual(task["id"], sub["id"])
        self.assertIsNotNone(sub["logs"][0]["id"])             # log landed on the subtask

    def test_done_marker_completes_and_is_consumed(self):
        client = _FakeClient()
        text = _tree("- 2026-06-10 13:00 14:00 [d] finish\n")  # existing task 300
        events, re = self._run(text, {"logs": {}}, client)
        self.assertEqual(client.completed, [300])              # task completed via API
        self.assertEqual(events[-1]["applied"], 2)             # create log + complete
        # [d] is a one-shot instruction: it does not survive into the applied buffer
        self.assertFalse(re["projects"][0]["tasklists"][0]["tasks"][0]["logs"][0]["done"])


class Tags(unittest.TestCase):
    """Task labels via a :LABELS: property line."""

    def _tree(self, tag_line="", task_prop=":TASK_ID: 300\n"):
        return (
            "#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=363603\n"
            "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n"
            "** L\n:PROPERTIES:\n:TASKLIST_ID: 200\n:END:\n"
            "*** Task\n:PROPERTIES:\n" + task_prop + tag_line + ":END:\n"
        )

    def test_parse_tags(self):
        task = T.parse_org(self._tree(":LABELS: bug, Backend\n"))["projects"][0]["tasklists"][0]["tasks"][0]
        self.assertEqual(task["tags"], ["bug", "Backend"])

    def test_parse_empty_tags_present(self):
        task = T.parse_org(self._tree(":LABELS:\n"))["projects"][0]["tasklists"][0]["tasks"][0]
        self.assertEqual(task["tags"], [])              # present but empty -> clear intent

    def test_missing_tags_line_absent(self):
        task = T.parse_org(self._tree())["projects"][0]["tasklists"][0]["tasks"][0]
        self.assertNotIn("tags", task)                  # no line -> no opinion

    def test_render_emits_tags(self):
        tasks = [{"id": 300, "title": "T", "tasklist_id": 200, "project_id": 100,
                  "parent_id": None, "tags": ["bug", "ui"]}]
        text = T.render_org([{"id": 100, "name": "P"}],
                            [{"id": 200, "name": "L", "project_id": 100}], tasks, [],
                            {"from": "2026-06-01", "to": "2026-06-30", "user_id": 1})
        self.assertIn(":LABELS: bug, ui", text)
        # round-trips back to the same tag list
        self.assertEqual(T.parse_org(text)["projects"][0]["tasklists"][0]["tasks"][0]["tags"],
                         ["bug", "ui"])

    def test_render_no_tags_is_plain_drawer(self):
        tasks = [{"id": 300, "title": "T", "tasklist_id": 200, "project_id": 100, "parent_id": None}]
        text = T.render_org([{"id": 100, "name": "P"}],
                            [{"id": 200, "name": "L", "project_id": 100}], tasks, [],
                            {"from": "2026-06-01", "to": "2026-06-30", "user_id": 1})
        self.assertNotIn("LABELS", text)
        self.assertIn(":PROPERTIES:\n:TASK_ID: 300\n:END:", text)

    def test_plan_sets_tags_when_changed(self):
        snap = {"logs": {}, "tasks": {"300": "Task"}, "task_tags": {"300": ["old"]}}
        plan = T.compute_plan(T.parse_org(self._tree(":LABELS: new, hot\n")), snap, 363603)
        self.assertEqual([a["type"] for a in plan["actions"]], ["set_task_tags"])
        a = plan["actions"][0]
        self.assertEqual((a["task"], a["tags"]), (300, ["new", "hot"]))

    def test_plan_no_action_when_tags_equal_modulo_case_order(self):
        snap = {"logs": {}, "tasks": {"300": "Task"}, "task_tags": {"300": ["Bug", "backend"]}}
        plan = T.compute_plan(T.parse_org(self._tree(":LABELS: backend, bug\n")), snap, 363603)
        self.assertEqual(plan["actions"], [])

    def test_plan_no_action_when_tags_line_absent(self):
        snap = {"logs": {}, "tasks": {"300": "Task"}, "task_tags": {"300": ["keep"]}}
        plan = T.compute_plan(T.parse_org(self._tree()), snap, 363603)
        self.assertEqual(plan["actions"], [])            # absent line never clears tags

    def test_plan_sets_tags_on_new_task_targets_ref(self):
        plan = T.compute_plan(T.parse_org(self._tree(":LABELS: fresh\n", task_prop="")),
                              {"logs": {}}, 363603)
        types = [a["type"] for a in plan["actions"]]
        self.assertEqual(types, ["create_task", "set_task_tags"])
        newtask = next(a for a in plan["actions"] if a["type"] == "create_task")
        self.assertEqual(plan["actions"][-1]["task"], {"ref": newtask["ref"]})


class Manage(unittest.TestCase):
    """Management buffers: same tree, no dates/logs, #+TEAMWORK_MANAGE marker."""

    def test_parse_manage_mode(self):
        p = T.parse_org("#+TEAMWORK_MANAGE: user=42\n#+TEAMWORK_ACCOUNT: work\n"
                        "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n")
        self.assertEqual(p["meta"]["mode"], "manage")
        self.assertEqual(p["meta"]["user"], "42")
        self.assertEqual(p["meta"]["account"], "work")

    def test_default_mode_is_timesheet(self):
        p = T.parse_org("#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=1\n* P\n")
        self.assertEqual(p["meta"]["mode"], "timesheet")

    def test_render_manage_has_marker_no_dates(self):
        text = T.render_manage([{"id": 100, "name": "P"}],
                               [{"id": 200, "name": "L", "project_id": 100}],
                               [{"id": 300, "title": "T", "tasklist_id": 200,
                                 "project_id": 100, "parent_id": None, "tags": ["x"]}],
                               {"user_id": 42, "account": "work"})
        self.assertIn("#+TEAMWORK_MANAGE: user=42", text)
        self.assertNotIn("#+TEAMWORK:", text)
        self.assertIn("*** T", text)
        self.assertIn(":LABELS: x", text)

    def test_manage_serialize_round_trips_mode(self):
        text = T.render_manage([{"id": 100, "name": "P"}],
                               [{"id": 200, "name": "L", "project_id": 100}], [],
                               {"user_id": 42, "account": "work"})
        p = T.parse_org(text)
        self.assertEqual(p["meta"]["mode"], "manage")
        self.assertIn("#+TEAMWORK_MANAGE:", T.serialize_parsed(p))

    def test_manage_plan_creates_list_and_task(self):
        text = ("#+TEAMWORK_MANAGE: user=42\n"
                "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n"
                "** New List\n"
                "*** New Task\n")
        plan = T.compute_plan(T.parse_org(text), {}, 42)
        self.assertEqual([a["type"] for a in plan["actions"]],
                         ["create_tasklist", "create_task"])


class ManageDescriptions(unittest.TestCase):
    """Task descriptions (free text under a task) in management mode."""

    def _tree(self, body):
        return ("#+TEAMWORK_MANAGE: user=42\n"
                "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n"
                "** L\n:PROPERTIES:\n:TASKLIST_ID: 200\n:END:\n" + body)

    def test_parse_description_body(self):
        body = ("*** A\n:PROPERTIES:\n:TASK_ID: 300\n:END:\n"
                "first line\nsecond line\n"
                "*** B\n:PROPERTIES:\n:TASK_ID: 500\n:END:\n")
        tasks = T.parse_org(self._tree(body))["projects"][0]["tasklists"][0]["tasks"]
        self.assertEqual(tasks[0]["description"], "first line\nsecond line")
        self.assertEqual(tasks[1]["description"], "")   # no body -> empty (authoritative)

    def test_description_not_parsed_in_timesheet_mode(self):
        # the same free text under a timesheet task must NOT become a description
        p = T.parse_org(
            "#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=1\n"
            "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n"
            "** L\n:PROPERTIES:\n:TASKLIST_ID: 200\n:END:\n"
            "*** A\n:PROPERTIES:\n:TASK_ID: 300\n:END:\nsome stray text\n")
        self.assertNotIn("description", p["projects"][0]["tasklists"][0]["tasks"][0])

    def test_render_manage_round_trips_description(self):
        tasks = [{"id": 300, "title": "A", "tasklist_id": 200, "project_id": 100,
                  "parent_id": None, "tags": [], "description": "line one\nline two"}]
        text = T.render_manage([{"id": 100, "name": "P"}],
                               [{"id": 200, "name": "L", "project_id": 100}], tasks,
                               {"user_id": 42})
        self.assertIn("line one", text)
        back = T.parse_org(text)["projects"][0]["tasklists"][0]["tasks"][0]
        self.assertEqual(back["description"], "line one\nline two")

    def test_plan_updates_changed_description(self):
        snap = {"tasks": {"300": "A"}, "task_desc": {"300": "old"}}
        body = "*** A\n:PROPERTIES:\n:TASK_ID: 300\n:END:\nbrand new text\n"
        plan = T.compute_plan(T.parse_org(self._tree(body)), snap, 42)
        self.assertEqual([a["type"] for a in plan["actions"]], ["update_task"])
        act = plan["actions"][0]
        self.assertEqual(act["description"], "brand new text")
        self.assertNotIn("title", act)                 # only the description changed

    def test_plan_clears_description(self):
        snap = {"tasks": {"300": "A"}, "task_desc": {"300": "had text"}}
        body = "*** A\n:PROPERTIES:\n:TASK_ID: 300\n:END:\n"   # body emptied
        plan = T.compute_plan(T.parse_org(self._tree(body)), snap, 42)
        self.assertEqual(plan["actions"][0]["description"], "")   # cleared, not left

    def test_plan_unchanged_description_no_action(self):
        snap = {"tasks": {"300": "A"}, "task_desc": {"300": "same"}}
        body = "*** A\n:PROPERTIES:\n:TASK_ID: 300\n:END:\nsame\n"
        self.assertEqual(T.compute_plan(T.parse_org(self._tree(body)), snap, 42)["actions"], [])

    def test_plan_new_task_carries_description(self):
        plan = T.compute_plan(T.parse_org(self._tree("*** Fresh\nfresh body\n")), {}, 42)
        create = next(a for a in plan["actions"] if a["type"] == "create_task")
        self.assertEqual(create["description"], "fresh body")


class TaskProperties(unittest.TestCase):
    """Due date / priority / assignee task properties in management mode."""

    def _tree(self, drawer_extra="", people=None):
        text = ("#+TEAMWORK_MANAGE: user=42\n"
                "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n"
                "** L\n:PROPERTIES:\n:TASKLIST_ID: 200\n:END:\n"
                "*** A\n:PROPERTIES:\n:TASK_ID: 300\n" + drawer_extra + ":END:\n")
        return text

    # -- format helpers --
    def test_norm_due(self):
        self.assertEqual(T._norm_due("20260820"), "2026-08-20")
        self.assertEqual(T._norm_due("2026-08-20"), "2026-08-20")
        self.assertEqual(T._norm_due(""), "")
        self.assertEqual(T._due_compact("2026-08-20"), "20260820")

    def test_norm_priority(self):
        self.assertEqual(T._norm_priority("None"), "")
        self.assertEqual(T._norm_priority("HIGH"), "high")

    # -- parse --
    def test_parse_properties(self):
        tk = T.parse_org(self._tree(
            ":DUE: 2026-08-20\n:URGENCY: high\n:ASSIGNEE: Jane Doe, John Roe\n"
        ))["projects"][0]["tasklists"][0]["tasks"][0]
        self.assertEqual(tk["due"], "2026-08-20")
        self.assertEqual(tk["priority"], "high")
        self.assertEqual(tk["assignee_names"], ["Jane Doe", "John Roe"])

    def test_missing_property_lines_absent(self):
        tk = T.parse_org(self._tree())["projects"][0]["tasklists"][0]["tasks"][0]
        for k in ("due", "priority", "assignee_names"):
            self.assertNotIn(k, tk)          # no line -> leave untouched

    # -- render round-trip (ids resolved to names via people map) --
    def test_render_manage_props_round_trip(self):
        tasks = [{"id": 300, "title": "A", "tasklist_id": 200, "project_id": 100,
                  "parent_id": None, "tags": [], "description": "",
                  "due": "2026-08-20", "priority": "medium",
                  "assignee_names": ["Jane Doe"]}]
        text = T.render_manage([{"id": 100, "name": "P"}],
                               [{"id": 200, "name": "L", "project_id": 100}], tasks,
                               {"user_id": 42})
        self.assertIn(":DUE: 2026-08-20", text)
        self.assertIn(":URGENCY: medium", text)
        self.assertIn(":ASSIGNEE: Jane Doe", text)
        back = T.parse_org(text)["projects"][0]["tasklists"][0]["tasks"][0]
        self.assertEqual((back["due"], back["priority"], back["assignee_names"]),
                         ("2026-08-20", "medium", ["Jane Doe"]))

    def test_timesheet_render_omits_props(self):
        tasks = [{"id": 300, "title": "A", "tasklist_id": 200, "project_id": 100,
                  "parent_id": None, "tags": [], "due": "2026-08-20", "priority": "high"}]
        text = T.render_org([{"id": 100, "name": "P"}],
                            [{"id": 200, "name": "L", "project_id": 100}], tasks, [],
                            {"from": "2026-06-01", "to": "2026-06-30", "user_id": 1})
        self.assertNotIn("DUE", text)     # timesheet buffers stay lean
        self.assertNotIn("URGENCY", text)

    # -- diff --
    def _snap(self, **over):
        s = {"tasks": {"300": "A"}, "task_due": {"300": ""}, "task_priority": {"300": ""},
             "task_assignees": {"300": []}, "people": {"7": "Jane Doe", "8": "John Roe"}}
        s.update(over)
        return s

    def test_plan_sets_due_and_priority(self):
        plan = T.compute_plan(T.parse_org(self._tree(":DUE: 2026-08-20\n:URGENCY: high\n")),
                              self._snap(), 42)
        self.assertEqual([a["type"] for a in plan["actions"]], ["update_task"])
        act = plan["actions"][0]
        self.assertEqual((act["due"], act["priority"]), ("2026-08-20", "high"))
        self.assertEqual(T._build_task_item(act)["due-date"], "20260820")

    def test_plan_resolves_assignee_names_to_ids(self):
        plan = T.compute_plan(T.parse_org(self._tree(":ASSIGNEE: Jane Doe\n")), self._snap(), 42)
        act = plan["actions"][0]
        self.assertEqual(act["assignees"], ["7"])            # name -> id
        self.assertEqual(T._build_task_item(act)["responsible-party-id"], "7")

    def test_plan_unknown_assignee_is_a_problem(self):
        plan = T.compute_plan(T.parse_org(self._tree(":ASSIGNEE: Nobody Here\n")), self._snap(), 42)
        self.assertTrue(any("unknown assignee" in p for p in plan["problems"]))

    def test_plan_unchanged_props_no_action(self):
        snap = self._snap(task_due={"300": "2026-08-20"}, task_priority={"300": "high"},
                          task_assignees={"300": ["Jane Doe"]})
        plan = T.compute_plan(
            T.parse_org(self._tree(":DUE: 2026-08-20\n:URGENCY: high\n:ASSIGNEE: Jane Doe\n")),
            snap, 42)
        self.assertEqual(plan["actions"], [])

    def test_plan_clears_due_with_empty_value(self):
        plan = T.compute_plan(T.parse_org(self._tree(":DUE:\n")),
                              self._snap(task_due={"300": "2026-08-20"}), 42)
        self.assertEqual(plan["actions"][0]["due"], "")
        self.assertEqual(T._build_task_item(plan["actions"][0])["due-date"], "")

    def test_new_task_carries_props_in_create(self):
        text = ("#+TEAMWORK_MANAGE: user=42\n"
                "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n"
                "** L\n:PROPERTIES:\n:TASKLIST_ID: 200\n:END:\n"
                "*** Fresh\n:PROPERTIES:\n:DUE: 2026-09-01\n:ASSIGNEE: John Roe\n:END:\n")
        plan = T.compute_plan(T.parse_org(text), self._snap(), 42)
        create = next(a for a in plan["actions"] if a["type"] == "create_task")
        item = T._build_task_item(create)
        self.assertEqual(item["due-date"], "20260901")
        self.assertEqual(item["responsible-party-id"], "8")


class ManageDone(unittest.TestCase):
    """The :DONE: property completes/reopens a task in management mode."""

    def _tree(self, done_line):
        return ("#+TEAMWORK_MANAGE: user=42\n"
                "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n"
                "** L\n:PROPERTIES:\n:TASKLIST_ID: 200\n:END:\n"
                "*** A\n:PROPERTIES:\n:TASK_ID: 300\n" + done_line + ":END:\n")

    def _snap(self, done):
        return {"tasks": {"300": "A"}, "task_done": {"300": done}}

    # -- render --
    def test_render_emits_done_state(self):
        tasks = [{"id": 300, "title": "A", "tasklist_id": 200, "project_id": 100,
                  "parent_id": None, "tags": [], "description": "", "done": True}]
        text = T.render_manage([{"id": 100, "name": "P"}],
                               [{"id": 200, "name": "L", "project_id": 100}], tasks,
                               {"user_id": 42})
        self.assertIn(":DONE: true", text)

    def test_render_emits_done_false_for_open_task(self):
        tasks = [{"id": 300, "title": "A", "tasklist_id": 200, "project_id": 100,
                  "parent_id": None, "tags": [], "description": ""}]  # no "done" -> open
        text = T.render_manage([{"id": 100, "name": "P"}],
                               [{"id": 200, "name": "L", "project_id": 100}], tasks,
                               {"user_id": 42})
        self.assertIn(":DONE: false", text)

    def test_timesheet_render_omits_done(self):
        tasks = [{"id": 300, "title": "A", "tasklist_id": 200, "project_id": 100,
                  "parent_id": None, "tags": [], "done": True}]
        text = T.render_org([{"id": 100, "name": "P"}],
                            [{"id": 200, "name": "L", "project_id": 100}], tasks, [],
                            {"from": "2026-06-01", "to": "2026-06-30", "user_id": 1})
        self.assertNotIn("DONE", text)

    # -- parse --
    def test_parse_done_true_false(self):
        for raw, want in ((":DONE: true\n", True), (":DONE: false\n", False)):
            tk = T.parse_org(self._tree(raw))["projects"][0]["tasklists"][0]["tasks"][0]
            self.assertEqual(tk["done"], want)

    def test_missing_done_line_absent(self):
        tk = T.parse_org(self._tree(""))["projects"][0]["tasklists"][0]["tasks"][0]
        self.assertNotIn("done", tk)          # no line -> leave completion untouched

    # -- diff --
    def test_plan_completes_when_flipped_true(self):
        plan = T.compute_plan(T.parse_org(self._tree(":DONE: true\n")), self._snap(False), 42)
        self.assertEqual([a["type"] for a in plan["actions"]], ["complete_task"])
        self.assertEqual(plan["actions"][0]["task"], 300)

    def test_plan_uncompletes_when_flipped_false(self):
        plan = T.compute_plan(T.parse_org(self._tree(":DONE: false\n")), self._snap(True), 42)
        self.assertEqual([a["type"] for a in plan["actions"]], ["uncomplete_task"])
        self.assertEqual(plan["actions"][0]["task"], 300)

    def test_plan_unchanged_done_no_action(self):
        self.assertEqual(
            T.compute_plan(T.parse_org(self._tree(":DONE: true\n")), self._snap(True), 42)["actions"], [])
        self.assertEqual(
            T.compute_plan(T.parse_org(self._tree(":DONE: false\n")), self._snap(False), 42)["actions"], [])

    def test_plan_new_task_created_done_targets_ref(self):
        text = ("#+TEAMWORK_MANAGE: user=42\n"
                "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n"
                "** L\n:PROPERTIES:\n:TASKLIST_ID: 200\n:END:\n"
                "*** Fresh\n:PROPERTIES:\n:DONE: true\n:END:\n")
        types = [a["type"] for a in T.compute_plan(T.parse_org(text), {}, 42)["actions"]]
        self.assertEqual(types, ["create_task", "complete_task"])

    def test_done_state_survives_snapshot_round_trip(self):
        p = T.parse_org(self._tree(":DONE: true\n"))
        snap = T.build_snapshot_from_parsed(p)
        self.assertEqual(snap["task_done"], {"300": True})


class ManageDeletions(unittest.TestCase):
    """Removing a task/tasklist heading in management mode deletes it in Teamwork."""

    def setUp(self):
        self.projects = [{"id": 100, "name": "P"}]
        self.tls = [{"id": 200, "name": "L", "project_id": 100}]
        self.tasks = [
            {"id": 300, "title": "A", "tasklist_id": 200, "project_id": 100,
             "parent_id": None, "tags": [], "description": "desc A"},
            {"id": 400, "title": "A1", "tasklist_id": 200, "project_id": 100,
             "parent_id": 300, "tags": [], "description": ""},
            {"id": 500, "title": "B", "tasklist_id": 200, "project_id": 100,
             "parent_id": None, "tags": [], "description": ""},
        ]
        self.snap = T.build_snapshot(self.projects, self.tls, self.tasks, [], {})

    def _plan(self, body):
        text = ("#+TEAMWORK_MANAGE: user=42\n"
                "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n" + body)
        return T.compute_plan(T.parse_org(text), self.snap, 42)

    _LIST = "** L\n:PROPERTIES:\n:TASKLIST_ID: 200\n:END:\n"
    _A = "*** A\n:PROPERTIES:\n:TASK_ID: 300\n:END:\ndesc A\n"
    _A1 = "**** A1\n:PROPERTIES:\n:TASK_ID: 400\n:END:\n"
    _B = "*** B\n:PROPERTIES:\n:TASK_ID: 500\n:END:\n"

    def test_remove_task_heading_deletes_it(self):
        plan = self._plan(self._LIST + self._A + self._A1)   # B removed
        self.assertEqual([(a["type"], a["id"]) for a in plan["actions"]],
                         [("delete_task", 500)])

    def test_remove_tasklist_deletes_list_only_children_pruned(self):
        plan = self._plan("")   # whole task-list L gone, project P kept
        self.assertEqual([(a["type"], a["id"]) for a in plan["actions"]],
                         [("delete_tasklist", 200)])   # no per-task deletes (cascade)

    def test_remove_parent_task_prunes_subtask(self):
        plan = self._plan(self._LIST + self._B)   # A and its subtask A1 removed
        self.assertEqual([(a["type"], a["id"]) for a in plan["actions"]],
                         [("delete_task", 300)])   # 400 pruned (descendant of 300)

    def test_remove_whole_project_deletes_nothing(self):
        # project heading itself removed -> hide (present_pids guard), never delete
        plan = T.compute_plan(T.parse_org("#+TEAMWORK_MANAGE: user=42\n"), self.snap, 42)
        self.assertEqual(plan["actions"], [])

    def test_timesheet_mode_never_deletes_tasks(self):
        # same removal in timesheet mode must NOT delete the task/list
        text = ("#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=42\n"
                "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n")   # everything removed
        plan = T.compute_plan(T.parse_org(text), self.snap, 42)
        kinds = {a["type"] for a in plan["actions"]}
        self.assertNotIn("delete_task", kinds)
        self.assertNotIn("delete_tasklist", kinds)

    def test_apply_executes_deletes(self):
        import io, json as _json, tempfile, contextlib
        T.BACKOFF_BASE = 0
        parsed = T.parse_org("#+TEAMWORK_MANAGE: user=42\n"
                             "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n"
                             + self._LIST + self._A + self._A1)   # B removed -> delete 500
        plan = T.compute_plan(parsed, self.snap, 42)

        class C(_FakeClient):
            def __init__(s): super().__init__(); s.deleted = []
            def delete_task(s, tid): s.deleted.append(tid)
        client = C()
        out = tempfile.NamedTemporaryFile("w+", suffix=".org", delete=False).name
        snap = tempfile.NamedTemporaryFile("w+", suffix=".json", delete=False).name
        b = io.StringIO()
        with contextlib.redirect_stdout(b):
            T.apply_stream(plan, client, parsed, out, snap)
        self.assertEqual(client.deleted, [500])
        self.assertEqual([_json.loads(l) for l in b.getvalue().splitlines()][-1]["applied"], 1)


class MoveTask(unittest.TestCase):
    """Deleting a heading and re-pasting it under a different list/parent keeps its
    TASK_ID, so management relocates the task in Teamwork rather than deleting it."""

    def setUp(self):
        self.projects = [{"id": 100, "name": "P"}]
        self.tls = [{"id": 200, "name": "L1", "project_id": 100},
                    {"id": 210, "name": "L2", "project_id": 100}]
        self.tasks = [
            {"id": 300, "title": "A", "tasklist_id": 200, "project_id": 100,
             "parent_id": None, "tags": [], "description": ""},
            {"id": 400, "title": "A1", "tasklist_id": 200, "project_id": 100,
             "parent_id": 300, "tags": [], "description": ""},
            {"id": 500, "title": "B", "tasklist_id": 200, "project_id": 100,
             "parent_id": None, "tags": [], "description": ""},
        ]
        self.snap = T.build_snapshot(self.projects, self.tls, self.tasks, [], {})

    _P = "* P\n:PROPERTIES:\n:PROJECT_ID: 100\n:END:\n"
    _L1 = "** L1\n:PROPERTIES:\n:TASKLIST_ID: 200\n:END:\n"
    _L2 = "** L2\n:PROPERTIES:\n:TASKLIST_ID: 210\n:END:\n"
    _A = "*** A\n:PROPERTIES:\n:TASK_ID: 300\n:END:\n"
    _A1 = "**** A1\n:PROPERTIES:\n:TASK_ID: 400\n:END:\n"
    _B = "*** B\n:PROPERTIES:\n:TASK_ID: 500\n:END:\n"

    def _plan(self, body, mode="manage"):
        head = ("#+TEAMWORK_MANAGE: user=42\n" if mode == "manage"
                else "#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=42\n")
        return T.compute_plan(T.parse_org(head + self._P + body), self.snap, 42)

    def _moves(self, plan):
        return [a for a in plan["actions"] if a["type"] == "move_task"]

    def test_move_top_level_task_to_other_list(self):
        # B re-pasted under L2; A (+ its subtask A1) stays put in L1.
        plan = self._plan(self._L1 + self._A + self._A1 + self._L2 + self._B)
        self.assertEqual([a["type"] for a in plan["actions"]], ["move_task"])
        mv = self._moves(plan)[0]
        self.assertEqual((mv["id"], mv["tasklist"]), (500, 210))
        self.assertNotIn("parent", mv)

    def test_promote_subtask_to_top_level(self):
        # A1 pulled out from under A to sit at the top level of L1.
        plan = self._plan(self._L1 + self._A + "*** A1\n:PROPERTIES:\n:TASK_ID: 400\n:END:\n"
                          + self._B)
        mv = self._moves(plan)
        self.assertEqual(len(mv), 1)
        self.assertEqual((mv[0]["id"], mv[0]["tasklist"], mv[0]["parent"]), (400, 200, 0))

    def test_demote_task_under_another_task(self):
        # B nested under A as a subtask; A1 stays a subtask of A (no spurious move).
        plan = self._plan(self._L1 + self._A + self._A1
                          + "**** B\n:PROPERTIES:\n:TASK_ID: 500\n:END:\n")
        mv = self._moves(plan)
        self.assertEqual(len(mv), 1)
        self.assertEqual((mv[0]["id"], mv[0]["parent"]), (500, 300))
        self.assertNotIn("tasklist", mv[0])

    def test_no_structural_change_no_move(self):
        plan = self._plan(self._L1 + self._A + self._A1 + self._B + self._L2)
        self.assertEqual(self._moves(plan), [])

    def test_timesheet_mode_never_moves(self):
        plan = self._plan(self._L1 + self._A + self._A1 + self._L2 + self._B, mode="timesheet")
        self.assertEqual(self._moves(plan), [])

    def test_move_into_brand_new_list_orders_after_create(self):
        # New list L3 (no TASKLIST_ID) that B is pasted into: create it, then move.
        body = (self._L1 + self._A + self._A1 + self._L2
                + "** L3\n:PROPERTIES:\n:END:\n" + self._B)
        plan = self._plan(body)
        types = [a["type"] for a in plan["actions"]]
        self.assertEqual(types, ["create_tasklist", "move_task"])
        create, move = plan["actions"]
        self.assertEqual(move["tasklist"], {"ref": create["ref"]})   # unresolved ref

    def test_apply_executes_move(self):
        import io, tempfile, contextlib
        T.BACKOFF_BASE = 0
        parsed = T.parse_org("#+TEAMWORK_MANAGE: user=42\n" + self._P
                             + self._L1 + self._A + self._A1 + self._L2 + self._B)
        plan = T.compute_plan(parsed, self.snap, 42)
        client = _FakeClient()
        out = tempfile.NamedTemporaryFile("w+", suffix=".org", delete=False).name
        snap = tempfile.NamedTemporaryFile("w+", suffix=".json", delete=False).name
        with contextlib.redirect_stdout(io.StringIO()):
            T.apply_stream(plan, client, parsed, out, snap)
        self.assertEqual(client.moved, [(500, 210, None)])


class Comments(unittest.TestCase):
    def _buf(self, body):
        return ("#+TITLE: Comments — X\n#+TEAMWORK_COMMENTS: task=555 user=1\n"
                "#+TEAMWORK_ACCOUNT: work\n\n" + body)

    def test_normalize_comment(self):
        n = T.normalize_comment({"id": "9", "author-firstname": "Ann", "author-lastname": "Lee",
                                 "datetime": "2026-06-10T09:30:00Z", "body": "hello\nthere"})
        self.assertEqual((n["id"], n["author"], n["datetime"], n["body"]),
                         (9, "Ann Lee", "2026-06-10 09:30", "hello\nthere"))

    def test_render_and_parse_round_trip(self):
        comments = [{"id": 9, "author": "Ann Lee", "datetime": "2026-06-10 09:30",
                     "body": "first line\nsecond line"}]
        text = T.render_comments(555, "My Task", comments, {"user_id": 1, "account": "work"})
        self.assertIn("#+TEAMWORK_COMMENTS: task=555 user=1", text)
        p = T.parse_comments(text)
        self.assertEqual(p["meta"]["task"], "555")
        self.assertEqual(p["meta"]["account"], "work")
        self.assertEqual(p["comments"][0]["id"], 9)
        self.assertEqual(p["comments"][0]["body"], "first line\nsecond line")

    def test_plan_create_edit_delete(self):
        buf = self._buf(
            "* Ann — 2026-06-10 09:30\n:PROPERTIES:\n:COMMENT_ID: 9\n:END:\nedited body\n\n"
            "* me\nbrand new comment\n")
        snap = {"task": "555", "comments": {"9": "old body", "8": "will be deleted"}}
        plan = T.compute_comment_plan(T.parse_comments(buf), snap)
        types = [a["type"] for a in plan["actions"]]
        self.assertEqual(sorted(types), ["create_comment", "delete_comment", "update_comment"])
        upd = next(a for a in plan["actions"] if a["type"] == "update_comment")
        self.assertEqual((upd["id"], upd["body"]), (9, "edited body"))
        dele = next(a for a in plan["actions"] if a["type"] == "delete_comment")
        self.assertEqual(dele["id"], 8)

    def test_plan_unchanged_no_action(self):
        buf = self._buf("* Ann\n:PROPERTIES:\n:COMMENT_ID: 9\n:END:\nsame body\n")
        snap = {"task": "555", "comments": {"9": "same body"}}
        self.assertEqual(T.compute_comment_plan(T.parse_comments(buf), snap)["actions"], [])

    def test_empty_new_heading_ignored(self):
        buf = self._buf("* me\n\n")   # heading with no body -> not posted
        self.assertEqual(T.compute_comment_plan(T.parse_comments(buf), {"comments": {}})["actions"], [])


class _CommentClient:
    def __init__(self):
        self._id = 900
        self.deleted, self.updated = [], []

    def create_comment(self, task_id, body):
        self._id += 1
        return self._id

    def update_comment(self, cid, body):
        self.updated.append((cid, body))

    def delete_comment(self, cid):
        self.deleted.append(cid)


class ApplyComments(unittest.TestCase):
    def setUp(self):
        T.BACKOFF_BASE = 0

    def test_apply_folds_created_id_and_persists(self):
        import io, json as _json, tempfile, contextlib
        buf = ("#+TEAMWORK_COMMENTS: task=555 user=1\n\n* me\nbrand new\n")
        parsed = T.parse_comments(buf)
        plan = T.compute_comment_plan(parsed, {"task": "555", "comments": {}})
        out = tempfile.NamedTemporaryFile("w+", suffix=".org", delete=False).name
        snap = tempfile.NamedTemporaryFile("w+", suffix=".json", delete=False).name
        b = io.StringIO()
        with contextlib.redirect_stdout(b):
            T.apply_comments(plan, _CommentClient(), 555, parsed, out, snap)
        events = [_json.loads(l) for l in b.getvalue().splitlines() if l.strip()]
        self.assertEqual(events[-1]["applied"], 1)
        reparsed = T.parse_comments(open(out).read())
        self.assertIsNotNone(reparsed["comments"][0]["id"])       # created id folded in
        self.assertEqual(_json.load(open(snap))["comments"], {str(reparsed["comments"][0]["id"]): "brand new"})


class Prefs(unittest.TestCase):
    """Per-account project filter must survive prefs rewrites (the 'reset' bug)."""

    def setUp(self):
        import tempfile
        self._dir = tempfile.mkdtemp()
        self._orig = T.CONFIG_DIR
        T.CONFIG_DIR = __import__("pathlib").Path(self._dir)

    def tearDown(self):
        T.CONFIG_DIR = self._orig

    def test_update_prefs_preserves_filter_across_hidden_rewrite(self):
        T.update_prefs("work", filter=[1, 2, 3])
        # a pull-like rewrite of hidden/shown must NOT drop the filter
        T.update_prefs("work", hidden={"9": "x"}, shown=[4, 5])
        p = T.load_prefs("work")
        self.assertEqual(p["filter"], [1, 2, 3])
        self.assertEqual(p["shown"], [4, 5])

    def test_filter_is_per_account(self):
        T.update_prefs("acctA", filter=[10])
        T.update_prefs("acctB", filter=[20])
        self.assertEqual(T.load_prefs("acctA")["filter"], [10])   # switching back keeps A's filter
        self.assertEqual(T.load_prefs("acctB")["filter"], [20])

    def test_view_flags_default_false(self):
        p = T.load_prefs("fresh")
        self.assertFalse(p["show_all_tasklists"])
        self.assertFalse(p["show_all_tasks"])

    def test_config_set_flips_one_flag_leaving_the_other(self):
        import io, json as _json, contextlib

        def run(**kw):
            a = type("A", (), {"account": "work", "show_all_tasklists": None,
                               "show_all_tasks": None})()
            for k, v in kw.items():
                setattr(a, k, v)
            b = io.StringIO()
            with contextlib.redirect_stdout(b):
                T.cmd_config_set(a)
            return _json.loads(b.getvalue())

        self.assertEqual(run(show_all_tasks="true"),
                         {"show_all_tasklists": False, "show_all_tasks": True})
        # the untouched flag persists across a second, unrelated set
        self.assertEqual(run(show_all_tasklists="yes"),
                         {"show_all_tasklists": True, "show_all_tasks": True})
        self.assertTrue(T.load_prefs("work")["show_all_tasks"])

    def _run(self, fn, **kw):
        import io, json as _json, contextlib
        a = type("A", (), kw)()
        b = io.StringIO()
        with contextlib.redirect_stdout(b):
            fn(a)
        return _json.loads(b.getvalue())

    def test_manage_state_reports_view_and_hidden(self):
        T.update_prefs("work", hidden={"9": "Hidden P"}, show_all_tasks=True)
        out = self._run(T.cmd_manage_state, account="work")
        self.assertEqual(out, {"view": {"all_tasklists": False, "all_tasks": True},
                               "hidden": {"9": "Hidden P"}})

    def test_manage_state_empty_defaults(self):
        out = self._run(T.cmd_manage_state, account="fresh")
        self.assertEqual(out, {"view": {"all_tasklists": False, "all_tasks": False},
                               "hidden": {}})

    def test_unhide_drops_id_and_keeps_the_rest(self):
        T.update_prefs("work", hidden={"9": "Hidden P", "10": "Other"})
        out = self._run(T.cmd_unhide, account="work", id="9")
        self.assertEqual(out, {"hidden": {"10": "Other"}})
        self.assertEqual(T.load_prefs("work")["hidden"], {"10": "Other"})

    def test_unhide_unknown_id_is_a_noop(self):
        T.update_prefs("work", hidden={"9": "Hidden P"})
        out = self._run(T.cmd_unhide, account="work", id="123")
        self.assertEqual(out, {"hidden": {"9": "Hidden P"}})


class ManageView(unittest.TestCase):
    """Management "show all" view: completed lists/tasks marked, flags in header."""

    def test_header_has_no_view_or_hidden_clutter(self):
        # The view flags and hidden list moved to prefs / `manage-state`; the
        # buffer keeps only the routing markers, no how-to comment block.
        meta = {"user_id": 42, "mode": "manage",
                "view": {"all_tasklists": True, "all_tasks": False}}
        text = T.render_manage([{"id": 1, "name": "P"}], [], [], meta,
                               hidden_names={"9": "Hidden P"})
        self.assertIn("#+TEAMWORK_MANAGE: user=42", text)   # routing marker stays
        self.assertNotIn("#+TEAMWORK_VIEW:", text)
        self.assertNotIn("#+TEAMWORK_HIDDEN:", text)
        self.assertNotIn("# No time filter here", text)     # how-to prose is gone
        self.assertNotIn("hidden 9", text)
        self.assertNotIn("#+TEAMWORK:", text)               # not mistaken for the marker

    def test_completed_tasklist_gets_marker_open_one_does_not(self):
        meta = {"user_id": 42, "mode": "manage", "view": {}}
        tls = [{"id": 200, "name": "Done", "project_id": 1, "completed": True},
               {"id": 201, "name": "Open", "project_id": 1, "completed": False}]
        text = T.render_manage([{"id": 1, "name": "P"}], tls, [], meta)
        self.assertIn("** Done\n:PROPERTIES:\n:TASKLIST_ID: 200\n:COMPLETED: t\n:END:", text)
        self.assertIn("** Open\n:PROPERTIES:\n:TASKLIST_ID: 201\n:END:", text)
        # the COMPLETED marker parses cleanly (no spurious problems / description)
        self.assertEqual(T.parse_org(text)["problems"], [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
