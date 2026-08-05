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


def _tree(logs, task_prop=":TW_TASK_ID: 300\n", tl_prop=":TW_TASKLIST_ID: 200\n",
          task_title="T", tl_name="L"):
    return (
        "#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=363603\n"
        "* P\n:PROPERTIES:\n:TW_PROJECT_ID: 100\n:END:\n"
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
            "* P\n:PROPERTIES:\n:TW_PROJECT_ID: 100\n:END:\n"
            "** L\n:PROPERTIES:\n:TW_TASKLIST_ID: 200\n:END:\n"
            "*** Task\n:PROPERTIES:\n:TW_TASK_ID: 300\n:END:\n" + extra
        )

    def test_parse_nested_subtasks(self):
        text = self._tree(
            "**** Sub A\n:PROPERTIES:\n:TW_TASK_ID: 400\n:END:\n"
            "***** Sub A1\n:PROPERTIES:\n:TW_TASK_ID: 410\n:END:\n"
            "**** Sub B\n:PROPERTIES:\n:TW_TASK_ID: 500\n:END:\n"
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
            "**** Sub\n:PROPERTIES:\n:TW_TASK_ID: 400\n:END:\n"
            "- 2026-06-10 09:00 10:00 on the subtask\n"
        )
        task = T.parse_org(text)["projects"][0]["tasklists"][0]["tasks"][0]
        self.assertEqual(task["logs"], [])                       # not on the parent
        log = task["subtasks"][0]["logs"][0]
        self.assertEqual((log["task_id"], log["description"]), (400, "on the subtask"))

    def test_subtask_without_parent_task_is_a_problem(self):
        text = (
            "#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=363603\n"
            "* P\n:PROPERTIES:\n:TW_PROJECT_ID: 100\n:END:\n"
            "** L\n:PROPERTIES:\n:TW_TASKLIST_ID: 200\n:END:\n"
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
            "**** Sub\n:PROPERTIES:\n:TW_TASK_ID: 400\n:END:\n"
            "- 42 2026-06-10 13:00 14:00 hi\n"))
        p2 = T.parse_org(T.serialize_parsed(p1))
        sub = p2["projects"][0]["tasklists"][0]["tasks"][0]["subtasks"][0]
        self.assertEqual((sub["id"], sub["logs"][0]["id"]), (400, 42))

    def test_snapshot_includes_subtasks(self):
        p = T.parse_org(self._tree("**** Sub\n:PROPERTIES:\n:TW_TASK_ID: 400\n:END:\n"))
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
            T.parse_org(self._tree("**** New Sub\n:PROPERTIES:\n:TW_TASK_ID: 400\n:END:\n")),
            snap, 363603)
        self.assertEqual([a["type"] for a in plan["actions"]], ["update_task"])
        self.assertIn("rename subtask", plan["actions"][0]["summary"])

    def test_plan_new_task_then_new_subtask_orders_parent_first(self):
        # brand-new task (no id) with a brand-new subtask + a log on the subtask:
        # create_task must precede create_subtask, which must target the task's ref.
        text = (
            "#+TEAMWORK: from=2026-06-01 to=2026-06-30 user=363603\n"
            "* P\n:PROPERTIES:\n:TW_PROJECT_ID: 100\n:END:\n"
            "** L\n:PROPERTIES:\n:TW_TASKLIST_ID: 200\n:END:\n"
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
                "**** Sub\n:PROPERTIES:\n:TW_TASK_ID: 400\n:END:\n"
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
        # brand-new task (no TW_TASK_ID) + a [d] log: complete must target the new ref
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
            "* P\n:PROPERTIES:\n:TW_PROJECT_ID: 100\n:END:\n"
            "** Existing\n:PROPERTIES:\n:TW_TASKLIST_ID: 200\n:END:\n"
            "*** Renamed Task\n:PROPERTIES:\n:TW_TASK_ID: 300\n:END:\n"
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
                        "* P\n:PROPERTIES:\n:TW_PROJECT_ID: 100\n:END:\n")
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

    def create_tasklist(self, pid, name):
        self._tid += 1
        return self._tid

    def create_task(self, tlid, title):
        if self.fail_task > 0:
            self.fail_task -= 1
            raise RuntimeError("boom task")
        self._tid += 1
        return self._tid

    def create_subtask(self, parent_id, title):
        self._tid += 1
        return self._tid

    def create_timelog(self, tkid, body):
        if self.fail_log > 0:
            self.fail_log -= 1
            raise RuntimeError("boom log")
        self._lid += 1
        return self._lid

    def update_task(self, *a):
        pass

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
            "* P\n:PROPERTIES:\n:TW_PROJECT_ID: 100\n:END:\n"
            "** L\n:PROPERTIES:\n:TW_TASKLIST_ID: 200\n:END:\n"
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
