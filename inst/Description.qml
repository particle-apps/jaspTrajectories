import QtQuick
import JASP.Module

Description
{
    name: "jaspTrajectories"
    title: qsTr("Trajectories")
    icon: "trajectories.svg"
    description: qsTr("Latent class growth analysis and growth mixture models for continuous and ordinal outcomes")
    requiresData: true
    preloadData: true

    Analysis
    {
        title: qsTr("Latent Class and Growth Mixture Models")
        menu: qsTr("LCGA and GMM")
        icon: "trajectories.svg"
        func: "Trajectories"
        qml: "Trajectories.qml"
    }
}
