from app import get_orders


def test_get_orders():
    orders = get_orders()
    assert len(orders) == 2
    assert all(o["amount"] > 0 for o in orders)
