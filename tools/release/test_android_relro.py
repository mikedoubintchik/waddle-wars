#!/usr/bin/env python3
"""Synthetic ELF64 regressions for RELRO page protection; no native tools needed."""
from __future__ import annotations

from dataclasses import dataclass
import struct
import unittest

from check_android_artifact import elf_failures


PT_LOAD = 1
PT_GNU_RELRO = 0x6474E552
PF_X = 1
PF_W = 2
PF_R = 4
PAGE = 0x4000


@dataclass(frozen=True)
class Segment:
    kind: int
    flags: int
    offset: int
    address: int
    filesz: int
    memsz: int
    align: int


def load(address: int, size: int, *, flags: int = PF_R | PF_W,
         offset: int | None = None, filesz: int | None = None) -> Segment:
    return Segment(PT_LOAD, flags, address if offset is None else offset,
                   address, size if filesz is None else filesz, size, PAGE)


def relro(address: int, size: int, *, offset: int | None = None,
          filesz: int | None = None) -> Segment:
    return Segment(PT_GNU_RELRO, PF_R, address if offset is None else offset,
                   address, size if filesz is None else filesz, size, 1)


def elf(*segments: Segment) -> bytes:
    """Make valid little-endian AArch64 headers and file-backed LOAD contents.

    The first read-only LOAD maps the ELF/program headers. File length follows
    LOADs, so malformed RELRO file ranges cannot manufacture their own backing.
    """
    headers = (load(0, PAGE, flags=PF_R), *segments)
    size = max(64 + 56 * len(headers),
               *(segment.offset + segment.filesz for segment in headers
                 if segment.kind == PT_LOAD))
    data = bytearray(size)
    data[:7] = b"\x7fELF\x02\x01\x01"
    struct.pack_into("<HHIQQQIHHHHHH", data, 16,
                     3, 183, 1, 0, 64, 0, 0, 64, 56, len(headers), 0, 0, 0)
    for index, segment in enumerate(headers):
        struct.pack_into("<IIQQQQQQ", data, 64 + 56 * index,
                         segment.kind, segment.flags, segment.offset,
                         segment.address, segment.address, segment.filesz,
                         segment.memsz, segment.align)
    return bytes(data)


class AndroidRelroTests(unittest.TestCase):
    def assert_relro_rejected(self, *segments: Segment, reason: str | None = None) -> None:
        failures = elf_failures(elf(*segments))
        self.assertTrue(any(error.startswith("RELRO[") for error in failures), failures)
        self.assertFalse(any(error.startswith("LOAD[") for error in failures), failures)
        if reason is not None:
            self.assertTrue(any(error.startswith("RELRO[") and reason in error
                                for error in failures), failures)

    def test_no_relro_is_structurally_valid(self) -> None:
        self.assertEqual(elf_failures(elf(load(0x8000, 0x4000))), [])

    def test_aligned_whole_load_is_valid(self) -> None:
        self.assertEqual(elf_failures(elf(load(0x8000, 0x4000),
                                        relro(0x8000, 0x4000))), [])

    def test_unaligned_whole_load_is_valid(self) -> None:
        self.assertEqual(elf_failures(elf(load(0x8200, 0x1100),
                                        relro(0x8200, 0x1100))), [])

    def test_unaligned_whole_load_with_separated_mutable_load_is_valid(self) -> None:
        self.assertEqual(elf_failures(elf(
            load(0x4000, 0xAF8, flags=PF_R | PF_X),
            load(0x8AF8, 0xA508, filesz=0xA090),
            load(0x16B88, 0x1200),
            relro(0x8AF8, 0xA508, filesz=0xA090),
        )), [])

    def test_aligned_partial_prefix_is_valid(self) -> None:
        self.assertEqual(elf_failures(elf(load(0x8000, 0x8000),
                                        relro(0x8000, 0x4000))), [])

    def test_aligned_interior_relro_is_valid(self) -> None:
        self.assertEqual(elf_failures(elf(load(0x8000, 0xC000),
                                        relro(0xC000, 0x4000))), [])

    def test_aligned_suffix_is_valid(self) -> None:
        self.assertEqual(elf_failures(elf(load(0x8000, 0x8000),
                                        relro(0xC000, 0x4000))), [])

    def test_partial_unaligned_end_catches_mutable_suffix(self) -> None:
        self.assert_relro_rejected(load(0x8000, 0x4000), relro(0x8000, 0x1000))

    def test_unaligned_start_catches_mutable_prefix(self) -> None:
        self.assert_relro_rejected(load(0x8000, 0x4000), relro(0x8800, 0x3800))

    def test_unaligned_interior_catches_both_mutable_edges(self) -> None:
        self.assert_relro_rejected(load(0x8000, 0xC000), relro(0xA000, 0x4000))

    def test_whole_load_catches_adjacent_mutable_bytes_at_start(self) -> None:
        self.assert_relro_rejected(load(0x8000, 0x100), load(0x8200, 0x1100),
                                   relro(0x8200, 0x1100))

    def test_whole_load_catches_adjacent_mutable_bytes_at_end(self) -> None:
        self.assert_relro_rejected(load(0x8000, 0x1000), load(0x9000, 0x1000),
                                   relro(0x8000, 0x1000))

    def test_whole_load_catches_adjacent_executable_bytes_at_start(self) -> None:
        self.assert_relro_rejected(load(0x8000, 0x200, flags=PF_R | PF_X),
                                   load(0x8200, 0x3E00), relro(0x8200, 0x3E00))

    def test_whole_load_catches_adjacent_executable_bytes_at_end(self) -> None:
        self.assert_relro_rejected(load(0x8000, 0x1000),
                                   load(0x9000, 0x1000, flags=PF_R | PF_X),
                                   relro(0x8000, 0x1000))

    def test_executable_containing_load_is_rejected(self) -> None:
        self.assert_relro_rejected(load(0x8000, 0x4000, flags=PF_R | PF_W | PF_X),
                                   relro(0x8000, 0x4000))

    def test_orphan_relro_is_rejected(self) -> None:
        self.assert_relro_rejected(load(0x8000, 0x4000),
                                   relro(0x10000, 0x4000, offset=0x8000))

    def test_nonwritable_containing_load_is_rejected(self) -> None:
        self.assert_relro_rejected(load(0x8000, 0x4000, flags=PF_R),
                                   relro(0x8000, 0x4000))

    def test_relro_spanning_two_loads_is_rejected(self) -> None:
        self.assert_relro_rejected(load(0x8000, 0x4000), load(0xC000, 0x4000),
                                   relro(0x8000, 0x8000))

    def test_two_containing_writable_loads_are_rejected(self) -> None:
        self.assert_relro_rejected(load(0x8000, 0x8000), load(0x8000, 0x4000),
                                   relro(0x8000, 0x4000))

    def test_empty_relro_is_rejected(self) -> None:
        self.assert_relro_rejected(load(0x8000, 0x4000), relro(0x8000, 0),
                                   reason="invalid segment size")

    def test_relro_filesz_greater_than_memsz_is_rejected(self) -> None:
        self.assert_relro_rejected(load(0x8000, 0x8000),
                                   relro(0x8000, 0x4000, filesz=0x4500),
                                   reason="invalid segment size")

    def test_relro_file_range_outside_elf_is_rejected(self) -> None:
        self.assert_relro_rejected(load(0x8000, 0x4000),
                                   relro(0x8000, 0x4000, offset=0x10000))

    def test_relro_file_range_overflow_is_rejected(self) -> None:
        self.assert_relro_rejected(load(0x8000, 0x4000),
                                   relro(0x8000, 0x4000, offset=(1 << 64) - 0x2000))

    def test_relro_virtual_range_overflow_is_rejected(self) -> None:
        self.assert_relro_rejected(
            load((1 << 64) - 0x4000, 0x3000, offset=0x4000),
            relro((1 << 64) - 0x2000, 0x4000, offset=0x6000, filesz=0x1000),
            reason="virtual range overflows",
        )


if __name__ == "__main__":
    unittest.main()
