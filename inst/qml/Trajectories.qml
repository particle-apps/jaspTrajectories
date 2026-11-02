import QtQuick
import QtQuick.Layouts
import JASP
import JASP.Controls

Form
{
    id: form
    info: qsTr("Fit latent class growth analysis (LCGA) or growth mixture models (GMM) to long-format data: one row per subject and measurement time. Continuous outcomes use Gaussian models. Ordinal outcomes use the lcmm threshold model on a latent process; this differs from an adjacent-category logit model. Review convergence and class sizes before interpreting a solution.")

    DropDown
    {
        id: outcomeType
        name: "outcomeType"
        label: qsTr("Outcome Type")
        values: [
            { label: qsTr("Continuous (Gaussian)"), value: "continuous" },
            { label: qsTr("Ordinal (Threshold Model)"), value: "ordinal" }
        ]
        startValue: "continuous"
        info: qsTr("For ordinal outcomes, select an ordered variable with numeric category codes and check its category order in JASP. The threshold model estimates ordered cutpoints on a latent scale; distances between the category labels are not assumed equal.")
    }

    VariablesForm
    {
        preferredHeight: 280 * jaspTheme.uiScale

        AvailableVariablesList
        {
            name: "allVariablesList"
        }

        AssignedVariablesList
        {
            name: "outcome"
            title: qsTr("Outcome")
            allowedColumns: ["scale", "ordinal"]
            allowTypeChange: true
            singleVariable: true
            info: qsTr("One continuous outcome or one ordinal outcome with numeric category codes. Missing outcomes are handled using the selected missing-data policy.")
        }

        AssignedVariablesList
        {
            name: "time"
            title: qsTr("Measurement Time")
            allowedColumns: ["scale"]
            singleVariable: true
            info: qsTr("A numeric time variable. Unequal spacing and different observed times across subjects are allowed. Time values must be observed.")
        }

        AssignedVariablesList
        {
            name: "subjectID"
            title: qsTr("Subject ID")
            allowedColumns: ["nominal"]
            allowTypeChange: true
            singleVariable: true
            info: qsTr("A numeric or text identifier shared by all observations from the same subject. IDs must be observed, and each subject-time combination must identify one row.")
        }
    }

    Section
    {
        title: qsTr("Model")
        expanded: true

        DropDown
        {
            id: model
            name: "model"
            label: qsTr("Analysis")
            values: [
                { label: qsTr("Latent Class Growth Analysis (LCGA)"), value: "lcga" },
                { label: qsTr("Growth Mixture Model (GMM)"), value: "gmm" }
            ]
            startValue: "lcga"
            info: qsTr("LCGA estimates a separate mean trajectory for each latent class without within-class random effects. GMM adds subject-specific random effects within each class.")
        }

        IntegerField
        {
            id: classCount
            name: "classes"
            label: qsTr("Number of Classes")
            defaultValue: 2
            min: 1
            max: 10
            info: qsTr("Fit one specified class count. Fit additional analyses with different class counts to compare solutions. A lower information criterion does not by itself establish the appropriate number of classes.")
        }

        DropDown
        {
            name: "degree"
            label: qsTr("Trajectory")
            values: [
                { label: qsTr("Linear"), value: "linear" },
                { label: qsTr("Quadratic"), value: "quadratic" },
                { label: qsTr("Cubic"), value: "cubic" }
            ]
            startValue: "linear"
            info: qsTr("Polynomial time effects are class-specific. The outcome mean is modelled directly for continuous outcomes and on the latent-process scale for ordinal outcomes.")
        }

        DropDown
        {
            id: randomEffects
            name: "randomEffects"
            label: qsTr("Random Effects")
            enabled: model.currentValue === "gmm"
            values: [
                { label: qsTr("Intercept"), value: "intercept" },
                { label: qsTr("Intercept and Linear Slope"), value: "interceptSlope" }
            ]
            startValue: "intercept"
            info: qsTr("The random-effects structure is separate from the polynomial mean trajectory. Quadratic and cubic means can use random intercepts or random intercepts and linear slopes.")
        }

        DropDown
        {
            name: "covariance"
            label: qsTr("Random-Effects Covariance")
            enabled: model.currentValue === "gmm" && randomEffects.currentValue === "interceptSlope"
            values: [
                { label: qsTr("Unstructured"), value: "unstructured" },
                { label: qsTr("Diagonal"), value: "diagonal" }
            ]
            startValue: "unstructured"
            info: qsTr("An unstructured matrix estimates intercept-slope covariance. A diagonal matrix fixes that covariance to zero. This choice has no effect with a random intercept alone.")
        }

        CheckBox
        {
            name: "classVariance"
            label: qsTr("Proportional Random-Effects Variance by Class")
            checked: false
            enabled: model.currentValue === "gmm" && classCount.value > 1
            info: qsTr("Allow a class-specific multiplier of the common random-effects covariance matrix. This is a proportional structure, not a separate unrestricted covariance matrix for each class.")
        }
    }

    Section
    {
        title: qsTr("Missing Data")

        DropDown
        {
            name: "missing"
            label: qsTr("Policy")
            values: [
                { label: qsTr("Available Outcomes (Observed-Data Likelihood)"), value: "available" },
                { label: qsTr("Complete Subjects"), value: "completeSubjects" }
            ]
            startValue: "available"
            info: qsTr("Available outcomes uses observed responses without filling missing cells, assuming ignorable missingness conditional on the model. Complete subjects excludes subjects with missing outcomes at recorded visits. Neither policy infers an unrecorded visit schedule. Subject IDs and times must be complete.")
        }
    }

    Section
    {
        title: qsTr("Estimation")

        IntegerField
        {
            name: "starts"
            label: qsTr("Random Starts")
            defaultValue: 10
            min: 1
            max: 1000
            info: qsTr("Number of preliminary random starts for a multiple-class model. The best preliminary solution is optimized to completion. Multiple starts reduce the risk of a poor local optimum but do not establish global optimality.")
        }

        IntegerField
        {
            name: "startIterations"
            label: qsTr("Iterations per Preliminary Start")
            defaultValue: 20
            min: 1
            max: 10000
        }

        IntegerField
        {
            name: "maxIterations"
            label: qsTr("Maximum Final Iterations")
            defaultValue: 500
            min: 1
            max: 10000
        }

        IntegerField
        {
            name: "seed"
            label: qsTr("Random Seed")
            defaultValue: 12345
            min: 1
            max: 2147483647
            fieldWidth: 100
        }
    }

    Section
    {
        title: qsTr("Output")
        expanded: true

        CheckBox { name: "parameterTable"; label: qsTr("Growth Coefficients"); checked: true }
        CheckBox { name: "classTable"; label: qsTr("Class Sizes and Classification"); checked: true }
        CheckBox
        {
            name: "observedFitPlot"
            label: qsTr("Observed vs Fitted Trajectories")
            checked: false
            info: qsTr("Compare observed and fitted means using each subject's posterior class probabilities. Both means use the same retained records. Ordinal means use the model's category codes. This is a descriptive check on the fitting data.")

            DropDown
            {
                id: observedFitGrouping
                name: "observedFitGrouping"
                label: qsTr("Time Grouping")
                values: [
                    { label: qsTr("Automatic"), value: "auto" },
                    { label: qsTr("Measurement Times"), value: "times" },
                    { label: qsTr("Time Intervals"), value: "intervals" }
                ]
                startValue: "auto"
                info: qsTr("Automatic uses each measurement time when there are at most 20 distinct retained times; otherwise it uses equal-width intervals. Within an interval, each record contributes its subject's class probability, so subjects with more records contribute more weight.")
            }

            IntegerField
            {
                name: "observedFitIntervals"
                label: qsTr("Number of Time Intervals")
                defaultValue: 10
                min: 2
                max: 100
                enabled: observedFitGrouping.currentValue !== "times"
            }

            CheckBox
            {
                name: "observedFitPanels"
                label: qsTr("Separate Panel per Class")
                checked: true
            }
        }

        CheckBox
        {
            name: "trajectoryPlot"
            label: qsTr("Class Trajectories")
            checked: true

            CheckBox
            {
                name: "confidenceBands"
                label: qsTr("95% Pointwise Confidence Bands")
                checked: false
                info: qsTr("Show model-based uncertainty at each plotted time, rather than a simultaneous confidence region for the entire curve. These intervals do not include uncertainty about the number of classes. For ordinal outcomes, curves and intervals summarize parameter draws of the expected category code.")
            }
        }
    }
}
