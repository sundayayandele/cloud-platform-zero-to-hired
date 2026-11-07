import pytest

from error_budget import Budget, main


def b(total, bad, elapsed=15, slo=0.995):
    return Budget(slo=slo, window_days=30, elapsed_days=elapsed, total=total, bad=bad)


def test_exactly_on_budget_burns_at_one():
    x = b(total=1_000_000, bad=5_000)          # 0.5% errors against a 0.5% budget
    assert x.burn_rate == pytest.approx(1.0)
    assert x.used == pytest.approx(0.5)        # halfway through the window, half the budget
    assert x.policy()[0] == "caution"          # 50% left is not "more than 50%"
    assert x.days_to_exhaustion is None        # lasts exactly to the end


def test_no_errors_is_normal_and_never_runs_out():
    x = b(total=1_000_000, bad=0)
    assert x.burn_rate == 0 and x.remaining == 1
    assert x.policy()[0] == "normal"
    assert x.days_to_exhaustion is None


def test_fast_burn_runs_out_soon_and_freezes():
    x = b(total=1_000_000, bad=9_000, elapsed=15)   # 0.9%: burn rate 1.8x
    assert x.burn_rate == pytest.approx(1.8)
    assert x.remaining == pytest.approx(0.1)
    assert x.policy()[0] == "freeze"
    assert x.days_to_exhaustion == pytest.approx(0.1 * 30 / 1.8)


def test_budget_gone():
    x = b(total=1_000_000, bad=20_000)
    assert x.remaining < 0
    assert x.policy()[0] == "exhausted"
    assert x.days_to_exhaustion == 0


def test_cli_prints_the_policy(capsys):
    assert main(["--slo", "99.5", "--total", "1200000", "--bad", "4100", "--elapsed-days", "12"]) == 0
    out = capsys.readouterr().out
    assert "Burn rate 0.68x" in out and "Policy: NORMAL" in out


@pytest.mark.parametrize("args", [["--slo", "150", "--total", "1", "--bad", "0", "--elapsed-days", "1"],
                                  ["--slo", "99", "--total", "10", "--bad", "11", "--elapsed-days", "1"],
                                  ["--slo", "99", "--elapsed-days", "1"]])
def test_bad_input_is_refused(args):
    with pytest.raises(SystemExit):
        main(args)
