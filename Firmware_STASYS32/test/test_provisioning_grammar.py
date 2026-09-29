import re
import unittest

PATTERN = re.compile(r"PROVISION_KEY:([0-9a-fA-F]{64})")
STATUS_PATTERN = re.compile(r"PROVISION_STATUS")


class ProvisioningGrammar(unittest.TestCase):
    def test_accepts_64_hex(self):
        self.assertIsNotNone(PATTERN.fullmatch("PROVISION_KEY:" + "ab" * 32))
        self.assertIsNotNone(PATTERN.fullmatch("PROVISION_KEY:" + "AB" * 32))

    def test_rejects_bad_input(self):
        self.assertIsNone(PATTERN.fullmatch("PROVISION_KEY:" + "ab" * 31))
        self.assertIsNone(PATTERN.fullmatch("PROVISION_KEY:" + "ab" * 33))
        self.assertIsNone(PATTERN.fullmatch("PROVISION_KEY:" + "zz" * 32))
        self.assertIsNone(PATTERN.fullmatch("PROVISION_KEY:"))

    def test_status_exact_command(self):
        self.assertIsNotNone(STATUS_PATTERN.fullmatch("PROVISION_STATUS"))
        self.assertIsNone(STATUS_PATTERN.fullmatch("PROVISION_STATUS "))
        self.assertIsNone(STATUS_PATTERN.fullmatch("PROVISION_STATUS:"))


if __name__ == "__main__":
    unittest.main()
