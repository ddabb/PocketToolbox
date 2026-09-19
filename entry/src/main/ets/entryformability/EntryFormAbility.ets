import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DailyPoemWidgetUtil } from '../common/utils/DailyPoemWidgetUtil';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    let formId: string = (want.parameters?.[formInfo.FormParam.IDENTITY_KEY] ?? '') as string;
    if (formId) {
      DailyPoemWidgetUtil.saveFormId(this.context, formId);
    }
    let formData: formBindingData.FormBindingData =
      formBindingData.createFormBindingData(DailyPoemWidgetUtil.buildCardData(this.context));
    return formData;
  }

  onUpdateForm(formId: string): void {
    let formData: formBindingData.FormBindingData =
      formBindingData.createFormBindingData(DailyPoemWidgetUtil.buildCardData(this.context));
    formProvider.updateForm(formId, formData).catch((error: BusinessError) => {
      console.error('[EntryFormAbility] updateForm failed: ' + JSON.stringify(error));
    });
  }

  onRemoveForm(formId: string): void {
    DailyPoemWidgetUtil.removeFormId(this.context, formId);
  }
}
