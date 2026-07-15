class ReportSummarizer:

    def summarize(self, record: dict):

        diagnosis = record.get("diagnosis")
        symptoms = record.get("symptoms", [])
        treatment = record.get("treatment_plan")

        summary = "📄 ملخص التقرير:\n\n"

        if diagnosis:
            summary += f"✅ التشخيص: {diagnosis}\n"

        if symptoms:
            summary += f"🩺 الأعراض: {', '.join(symptoms)}\n"

        if treatment:
            summary += f"💊 العلاج: {treatment}\n"

        summary += "\n💡 يُنصح بمتابعة الطبيب."

        return summary
