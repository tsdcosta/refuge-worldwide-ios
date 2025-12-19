//
//  ScheduleHelpers.swift
//  Refuge Worldwide
//
//  Created by Tiago Costa on 12/18/25.
//

import Foundation

// MARK: - Day grouping model
struct ScheduleDay: Identifiable {
    let id = UUID()
    let date: Date
    let shows: [ShowItem]
}

// MARK: - Array extension to group shows by day
extension Array where Element == ShowItem {
    func groupedByDay() -> [ScheduleDay] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: self) { show in
            guard let date = show.date else { return Date.distantPast }
            return calendar.startOfDay(for: date)
        }

        return grouped.keys.sorted()
            .map { day in
                ScheduleDay(date: day, shows: grouped[day]?.sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) } ?? [])
            }
    }
}
