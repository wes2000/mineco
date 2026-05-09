extends GutTest

# Chat is the autoload — accessing /root/Chat after _ready spawns the
# autoload in tests too.

func before_each() -> void:
	# Clear the buffer so tests don't pollute each other.
	if Chat != null:
		Chat._buffer.clear()

func test_buffer_keeps_last_six_messages() -> void:
	for i in range(10):
		Chat._append_local("user", "msg_%d" % i, 0)
	var lines: Array = Chat.get_recent_lines()
	assert_eq(lines.size(), 6)
	assert_eq(String(lines[0]["text"]), "msg_4")
	assert_eq(String(lines[5]["text"]), "msg_9")

func test_messages_have_timestamp_and_author() -> void:
	Chat._append_local("Alice", "hello", 1234)
	var line: Dictionary = Chat.get_recent_lines()[0]
	assert_eq(String(line["author"]), "Alice")
	assert_eq(String(line["text"]), "hello")
	assert_eq(int(line["ts"]), 1234)

func test_get_recent_lines_returns_a_copy() -> void:
	Chat._append_local("a", "x", 0)
	var snapshot: Array = Chat.get_recent_lines()
	Chat._append_local("b", "y", 0)
	# Snapshot should be unchanged after a subsequent append.
	assert_eq(snapshot.size(), 1)
	assert_eq(String(snapshot[0]["text"]), "x")
