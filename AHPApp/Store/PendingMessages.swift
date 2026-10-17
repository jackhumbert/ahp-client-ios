import AgentHostProtocol

extension ChatState {
    /// Messages waiting to be sent, in the order the host will take them, each
    /// with the kind it was sent as.
    ///
    /// Since 1.1.0 steering and queued messages share `queuedMessages`, each
    /// entry tagged with its `kind`, and `steeringMessage` is a deprecated
    /// mirror of a steering entry already in that list. A 1.0.0 host keeps
    /// steering only in `steeringMessage`; it is added at the front then, since
    /// it joins the turn in flight, ahead of anything queued after it.
    var pendingMessages: [PendingMessage] {
        var list = (queuedMessages ?? []).map { entry in
            var entry = entry
            // An entry from before 1.1.0 has no kind; it is queued unless it
            // is the one the mirror names.
            if entry.kind == nil {
                entry.kind = entry.id == steeringMessage?.id ? .steering : .queued
            }
            return entry
        }
        if let mirror = steeringMessage, !list.contains(where: { $0.id == mirror.id }) {
            list.insert(PendingMessage(id: mirror.id, kind: .steering, message: mirror.message), at: 0)
        }
        return list
    }
}
