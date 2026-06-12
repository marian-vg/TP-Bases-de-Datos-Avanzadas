_total_score: int = 0


def add_score(points: int):
    global _total_score
    _total_score += points


def get_score() -> int:
    return _total_score


def reset_score():
    global _total_score
    _total_score = 0
