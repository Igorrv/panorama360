import Foundation

/// Creates navigable hotspots between adjacent scenes automatically. A real-
/// estate tour is a walk through a sequence of rooms, so linking each scene to
/// its neighbours by capture order (`project.scenes`) removes the tedious manual
/// hotspot step — the author only adjusts placement, never starts from zero.
///
/// Placement is guided by each scene's `initialYaw`: the forward link sits
/// straight ahead on entry, the back link behind (opposite the entry view), both
/// at eye level. **Idempotent**: running twice adds nothing — a scene already
/// linking to a target is left alone, so manually-authored links survive.
public enum AutoLinker {

    /// Returns a copy of `project` with neighbour links added to every scene.
    public static func autoLink(_ project: Project) -> Project {
        var p = project
        let n = p.scenes.count
        guard n > 1 else { return p }
        for i in 0..<n {
            var scene = p.scenes[i]
            // Forward link to the next scene (straight ahead on entry).
            if i + 1 < n {
                addLink(in: &scene, to: p.scenes[i + 1].id,
                        label: "Próximo cômodo", icon: "arrow.forward.circle.fill",
                        pitch: scene.initialPitch, yaw: scene.initialYaw)
            }
            // Back link to the previous scene (behind, opposite the entry view).
            if i - 1 >= 0 {
                addLink(in: &scene, to: p.scenes[i - 1].id,
                        label: "Cena anterior", icon: "arrow.backward.circle.fill",
                        pitch: scene.initialPitch, yaw: scene.initialYaw + .pi)
            }
            p.scenes[i] = scene
        }
        p.updatedAt = Date()
        return p
    }

    /// Appends a link to `target` only if the scene doesn't already link there,
    /// so re-running `autoLink` never duplicates work or clobbers manual edits.
    private static func addLink(in scene: inout TourScene, to target: UUID,
                                label: String, icon: String,
                                pitch: Double, yaw: Double) {
        guard !scene.hotspots.contains(where: { $0.targetSceneID == target }) else { return }
        scene.hotspots.append(Hotspot(label: label, iconName: icon,
                                      pitch: pitch, yaw: yaw, targetSceneID: target))
    }
}
