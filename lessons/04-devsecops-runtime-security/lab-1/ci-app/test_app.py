from app import get_items


def test_get_items_returns_non_empty_list():
    items = get_items()
    assert len(items) == 2
    assert items[0]["name"] == "k8s-handbook"
    assert all(item["price"] > 0 for item in items)
