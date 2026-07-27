import unittest

from build_unscroll import PRESERVED_ROUTES, UNSCROLL_ROUTES


class RoutePolicyTests(unittest.TestCase):
    def test_normal_instagram_routes_are_preserved(self) -> None:
        self.assertTrue(set(PRESERVED_ROUTES).isdisjoint(UNSCROLL_ROUTES))

    def test_algorithmic_reels_routes_are_blocked(self) -> None:
        required_routes = {
            b"/clips/discover/",
            b"/clips/playlist_chaining/",
            b"/discover/explore_clips/",
            b"/feed/injected_reels_media/",
        }
        self.assertTrue(required_routes.issubset(UNSCROLL_ROUTES))


if __name__ == "__main__":
    unittest.main()
