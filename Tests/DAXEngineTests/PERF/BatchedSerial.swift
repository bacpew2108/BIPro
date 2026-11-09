// BatchedSerial.swift
// Công tắc `BatchedIteration.overrideEnabled` và bộ đếm `takenCount` là trạng thái toàn cục. Mọi suite đụng tới chúng
// nằm trong suite cha này để chạy tuần tự với nhau (`.serialized` của suite cha áp cho các suite con), nếu không các
// suite khác nhau chạy song song sẽ đổi công tắc và bộ đếm của nhau giữa chừng.

import Testing

@Suite(.serialized) enum BatchedSerial {}
